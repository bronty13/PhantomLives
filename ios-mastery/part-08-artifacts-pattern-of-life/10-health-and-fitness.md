---
title: "Health & fitness"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 10
est_time: "45 min read + 20 min labs"
prerequisites: [knowledgec-db-deep-dive, bfu-vs-afu-and-data-protection-classes]
tags: [ios, forensics, health, fitness, healthkit, pattern-of-life, dfir]
last_reviewed: 2026-06-26
---

# Health & fitness

> **In one sentence:** `healthdb_secure.sqlite` is a per-second physiological and locomotion log that no investigator should overlook — it can place a person *walking at a specific minute*, prove an Apple Watch was paired and when, and reconstruct a sleep/activity presence timeline — but its samples are Data-Protection class **Protected Unless Open** (Class B), whose key Apple relinquishes ~10 minutes after the device locks, so you get it only from a device that is **unlocked, or only just locked** — never one left sitting locked or rebooted to BFU.

## Why this matters

The other Part 08 stores tell you what the *device* did: which app was in focus ([[01-knowledgec-db-deep-dive]]), what was on screen ([[02-biome-and-segb-streams]]), where the phone was ([[07-location-history]]). The Health store tells you what the **body carrying the device** did. A step-count sample is a denial that the phone sat motionless on a nightstand. A heart-rate series climbing from 60 to 150 bpm at 02:14 is a person who got up and moved. A `workouts` row with a per-second GPS track is a route map drawn by exertion, not by the location daemon. A sleep-analysis sample is a claim about when someone was *in bed*.

And the data is doubly valuable because it is **multi-device by construction**. The phone's `healthdb_secure.sqlite` is the consolidated hub: it ingests samples from the phone's own motion coprocessor *and* from a paired Apple Watch, AirPods, third-party apps, and Bluetooth scales/monitors — each tagged with its origin. So the same file that gives you step counts also proves *which devices were paired to this phone, and across which OS versions*. Examiners routinely under-mine it. Don't.

## Concepts

### Where it lives and what the files are

Everything is under one directory in a full-file-system extraction:

```
/private/var/mobile/Library/Health/
├── healthdb.sqlite              # metadata DB: sources, the per-type schema registry, sync state
├── healthdb.sqlite-wal
├── healthdb.sqlite-shm
├── healthdb_secure.sqlite       # THE store: samples, workouts, heart rate, provenance — the heavy data
├── healthdb_secure.sqlite-wal   # uncheckpointed writes — copy it too, or you lose the most recent samples
├── healthdb_secure.sqlite-shm
├── healthdb_secure.hfd          # "high-frequency data" — per-second series blobs (HR, workout GPS, etc.)
├── healthdb_secure.hfd-wal
└── ... (nanosync bookkeeping, cache files)
```

Two databases, one relationship: **`healthdb.sqlite` is the dictionary, `healthdb_secure.sqlite` is the encyclopedia.** `healthdb.sqlite` holds the *source* records (which app/device is allowed to write which type) and the type-registry; `healthdb_secure.sqlite` holds the actual measurements, with frequent integer references back into the metadata DB. In practice the secure DB is where 95% of your queries run, but you cross-reference the plain DB when you need to resolve a source or a type-name.

The third heavyweight, **`healthdb_secure.hfd`**, is *not* SQLite — it is Apple's "high-frequency data" container. Per-second series that would bloat a relational table (every heartbeat during a workout, a GPS fix every second of a run, the beat-to-beat series behind an HRV reading) are written here as packed binary and referenced from the SQLite series tables by key. The forensically juicy one: `healthdb_secure.hfd` stores a *timestamp + latitude + longitude every second* for recent distance-bearing workouts — a route track that is independent of the location daemon's caches.

> 🖥️ **macOS contrast:** There is **no Health store on macOS.** The Mac you just spent a course dissecting has `knowledgeC.db`, `chat.db`, `Photos.sqlite` — but no `healthdb_secure.sqlite`, because the iPhone *is* the HealthKit hub for the whole device constellation. (macOS only ever sees Health data through the Fitness app's iCloud-synced summaries, never as a local primary store.) This is the inverse of `knowledgeC.db`, which exists on both platforms: Health is phone-resident, and the Watch-sourced samples in it are unique to the phone — the only consolidated copy anywhere short of E2E-encrypted iCloud.

### The protection caveat — Class B, the 10-minute lock window, and BFU

This is the single most important operational fact in the lesson, so it goes first among the mechanics. Apple's Platform Security guide splits the Health store into two protection tiers:

- **The primary samples (`healthdb_secure.sqlite`) are Data-Protection class "Protected Unless Open" — `NSFileProtectionCompleteUnlessOpen` (Class B).** Apple documents a Health-specific grace: *"access to the data is relinquished 10 minutes after the device locks."* New samples can still be *written* while locked — Class B wraps with the always-present public class key — but the **private** key needed to *read* an already-closed file is gone ~10 minutes after lock.
- **The metadata/management DB (`healthdb.sqlite`) is class "Protected Until First User Authentication" — `NSFileProtectionCompleteUntilFirstUserAuthentication` (Class C)** — the AFU-resident class, available from first unlock until reboot.

Concretely (see [[02-bfu-vs-afu-and-data-protection-classes]] and [[03-passcode-bfu-afu-and-inactivity]]):

| Device state | `healthdb_secure.sqlite` (samples, Class B) | `healthdb.sqlite` (metadata, Class C) |
|---|---|---|
| **Unlocked**, or **locked < ~10 min** | **Readable** (private key still resident) | Readable |
| **AFU, locked > ~10 min** | **Ciphertext** — the Class-B private key is gone, even to a full-file-system tool | Readable (Class C persists to reboot) |
| **BFU** (booted, never unlocked) | **Nothing** | **Nothing** |

This is sharper than the usual "AFU = readable" rule of thumb, and it is the trap: **the Health *samples* do not survive an extended screen-lock the way ordinary Class-C app data does.** A phone seized powered-off, one that hit its **72-hour inactivity reboot** (iOS reboots itself back to BFU after ~72 h with no unlock — see the baseline), *or one that simply sat locked on the evidence bench for fifteen minutes* yields no decryptable samples even to a full-file-system tool — the bytes are inert ciphertext and the key is gone. The corollary for seizure procedure is brutal and simple: **a Health-bearing phone must be kept awake and unlocked** (disable auto-lock; keep it from idling), not merely "AFU." Faraday + power + a documented "do not let it lock or sleep" note belongs in your seizure SOP. (A commercial box that acquires while the device is held *unlocked*, or with the passcode in hand, gets the full store — the 10-minute window is what bites a locked-bench seizure; re-verify the exact behavior for the device's iOS version.)

> 🔬 **Forensics note:** The samples store is *more* protected than many neighbours. `knowledgeC.db` and much of Biome/SEGB survive a screen-lock because they are Class C/D (resident until reboot, or always). The Health *samples* are Class B — sealed back to ciphertext minutes after lock, the same family as the most sensitive Keychain items, and consistent with the sibling lesson's note that Apple promotes Health to a sealed-at-lock class. The practical tell: an extraction with a populated `knowledgeC.db` *and* `healthdb.sqlite` but an *empty or undecryptable* `healthdb_secure.sqlite` is the signature of a device acquired locked-past-the-window — the Class-B samples went dark while the lower classes stayed live. Note the lock state and time-since-unlock at seizure; it explains the gap.

> ⚖️ **Authorization:** Health data is special-category / sensitive personal data under essentially every privacy regime (HIPAA-adjacent in the US, "special category" under GDPR, etc.). Even with lawful authority to search a device, a warrant scoped to "communications" does not automatically reach a person's menstrual cycle, cardiac events, or sleep records. Confirm your authority *names* health/biometric data, or scope your queries to exclude it. The richness of this store cuts both ways.

### The acquisition routes that even reach it

Because of this protection, only a subset of acquisition methods produce Health at all:

- **Full-file-system extraction (unlocked / freshly-locked device)** — the gold path. checkm8/usbliter8 on a supported SoC, a kernel/BootROM exploit, or a commercial box (GrayKey/Cellebrite) — but the Class-B samples decrypt only if the device is unlocked, or within the ~10-minute post-lock window, at the moment keys are pulled. See [[05-full-file-system-acquisition]].
- **Encrypted iTunes/Finder backup** — Health is included **only when a backup password is set.** A passwordless backup deliberately omits it. With the password, decrypt the backup and the Health files are inside. See [[03-the-itunes-finder-backup-format]] and [[07-decrypting-backups-and-images]].
- **iCloud** — Health syncs to iCloud **end-to-end encrypted regardless of Advanced Data Protection**, keyed to the account + a trusted device or the HSA2/escrow path. So ADP being off does *not* hand you Health from the cloud the way it hands you a plain iCloud backup; Health is in the E2E set either way. See [[06-icloud-acquisition-and-advanced-data-protection]].

A *passwordless* logical backup gives you essentially nothing here — a classic trap covered under Pitfalls.

### The relational core: `samples` → everything

The schema looks sprawling, but it radiates from one hub table. **`samples`** is the spine; almost every other table is a per-shape extension hanging off the same primary key, `data_id`.

```
                          ┌────────────────────────────┐
                          │           samples          │
                          │  data_id (PK)              │
                          │  start_date  end_date      │  (Mac Absolute Time, REAL seconds)
                          │  data_type   (int code)    │
                          └─────────────┬──────────────┘
            data_id ──────┬─────────────┼─────────────┬──────────────┐
                          ▼             ▼             ▼              ▼
              ┌───────────────┐ ┌──────────────┐ ┌─────────┐ ┌───────────────┐
              │quantity_samples│ │category_samples│ │workouts │ │ ecg_samples … │
              │ quantity       │ │ value (enum)  │ │ duration│ │               │
              │ original_unit ─┼─→unit_strings   │ │ total_* │ │               │
              └───────────────┘ └──────────────┘ └────┬────┘ └───────────────┘
                                                        │ data_id = owner_id
                                                        ▼
                                              workout_activities / workout_events
   objects.data_id = samples.data_id
        objects.provenance ────────────────────────────────────────────► data_provenances.ROWID
   metadata_values.object_id = objects.data_id ; metadata_values.key_id = metadata_keys.ROWID
```

The tables you will actually touch:

| Table | Keyed by | What it holds |
|---|---|---|
| `samples` | `data_id` | The universal envelope: every sample's `start_date`, `end_date`, and `data_type` integer. Entry point for *every* query. |
| `quantity_samples` | `data_id` | The numeric value (`quantity`, plus `original_quantity` / `original_unit`) for quantity types — steps, distance, heart rate, energy, etc. |
| `category_samples` | `data_id` | Enumerated values for category types — sleep stages, mindful minutes, menstrual flow, etc. (`value` is a type-specific code.) |
| `workouts` | `data_id` | One row per workout: `duration`, `total_energy_burned`, `total_distance`, `total_basal_energy_burned`, goal info. |
| `workout_activities`, `workout_events` | `owner_id = workouts.data_id` | Per-activity segments (a multi-sport workout) and discrete events (pause, lap, marker). `activity_type` here is the stable `HKWorkoutActivityType` enum. |
| `objects` | `data_id` | The provenance/identity layer: `uuid`, `creation_date`, and **`provenance`** → `data_provenances.ROWID`. Every sample has a matching `objects` row. |
| `data_provenances` | `ROWID` | **Which device/app/OS produced the sample.** The device-pairing goldmine (next section). |
| `metadata_values` / `metadata_keys` | `object_id` / `key_id` | Arbitrary key/value extras per sample — latitude, longitude, weather, timezone, device-name, sync identifiers. |
| `correlations` | `samples.data_id` ↔ `object` | Groups co-measured samples — a blood-pressure reading is a correlation linking a systolic + diastolic sample; a food entry links its nutrients. |
| `unit_strings` | `ROWID` | Unit lookup (`count`, `m`, `kcal`, `count/min`) referenced by `quantity_samples.original_unit`. |
| `quantity_sample_series` / `quantity_series_data`, `location_series_data` | series keys / `hfd_key` | Pointers into `healthdb_secure.hfd` for the per-second blobs (HR series, workout GPS track). |

A complete quantity reading is therefore a join:

```sql
SELECT samples.data_id,
       samples.data_type,
       datetime(samples.start_date + 978307200, 'unixepoch') AS start_utc,
       datetime(samples.end_date   + 978307200, 'unixepoch') AS end_utc,
       quantity_samples.quantity,
       unit_strings.unit_string
FROM samples
JOIN quantity_samples ON quantity_samples.data_id = samples.data_id
LEFT JOIN unit_strings ON unit_strings.ROWID = quantity_samples.original_unit
ORDER BY samples.start_date;
```

### Timestamps: Mac Absolute Time (again)

Every `*_date` column here is **Mac Absolute Time** — seconds since `2001-01-01 00:00:00 UTC`, stored as a REAL (so you'll see fractional seconds). Convert exactly as you did for `knowledgeC.db`:

```
unix_seconds = mac_absolute_seconds + 978307200
datetime(start_date + 978307200, 'unixepoch')           -- UTC
datetime(start_date + 978307200, 'unixepoch', 'localtime')  -- examiner-local; usually WRONG for the subject
```

Prefer UTC in the database and resolve the *subject's* local time from the per-sample timezone (`data_provenances.tz_name`, or a `metadata_values` `HKTimeZone` key), not from your workstation's `localtime`. See [[00-the-ios-timestamp-zoo]] — Health is one more store in the zoo, and it is uniform Mac-Absolute, which is a small mercy.

### `data_type`: enumerate it, never hardcode it

`samples.data_type` is an integer that says *what kind of sample this is*. It is **Apple's internal `HKObjectType` ordinal — and it is NOT stable across iOS versions.** New types are inserted into the enumeration as Apple adds them, which can shift the codes of later entries between major releases. Numbers seen on one image:

| `data_type` (observed) | Meaning |
|---|---|
| 7 | Step count |
| 8 | Distance (walking/running) |
| 12 | Flights climbed |
| 79 | Workout |
| 80 | Blood pressure (correlation) |
| 102 | Location series |
| 144 | Electrocardiogram (ECG) |
| 147 | Low-heart-rate event (category) |

**Treat that table as illustrative, not authoritative.** The correct procedure on every new image is to *enumerate the codes present in this database* and resolve them against the device's own type registry, rather than pasting a number table from a blog. Two reliable ways:

```sql
-- 1) See what's actually in THIS image and how much of each
SELECT data_type, COUNT(*) AS n,
       datetime(MIN(start_date)+978307200,'unixepoch') AS first,
       datetime(MAX(start_date)+978307200,'unixepoch') AS last
FROM samples
GROUP BY data_type
ORDER BY n DESC;
```

```sql
-- 2) Resolve codes to names using the device's OWN registry where present
--    (healthdb.sqlite carries a type/objects registry; exact table name varies by version —
--     inspect with .schema and prefer the on-device mapping over any external list)
```

If you must label types and the device registry is unavailable, derive the mapping from the iOS version's HealthKit headers/SDK (via [[02-the-dyld-shared-cache]]) rather than a static blog table. A mislabelled `data_type` is how "resting heart rate" gets reported as "step count" in court. The mechanism (enumerate → resolve against this version) is durable; the integers are perishable.

> 🔬 **Forensics note:** By contrast, `workout_activities.activity_type` is the **public `HKWorkoutActivityType` enum** (running, walking, cycling, swimming, …) and is far more stable than the internal `samples.data_type`, because it's a documented API surface Apple avoids renumbering. Still verify the exact integer→name map against the SDK for the device's iOS version before testifying to "this was a *cycling* workout."

### Category samples: decoding sleep and the other enumerated types

Quantity types carry a number; **category types carry an enumerated code** in `category_samples.value`, and that code is type-specific. The one you will care about most is **sleep analysis**, because it speaks directly to "was the subject conscious and using the device?" Its `value` is the public `HKCategoryValueSleepAnalysis` enum:

| `value` (sleep) | Meaning |
|---|---|
| 0 | In bed |
| 1 | Asleep (unspecified) |
| 2 | Awake |
| 3 | Asleep — core |
| 4 | Asleep — deep |
| 5 | Asleep — REM |

So a "was-asleep" window is the union of `start_date`/`end_date` for rows where `value` ∈ {1,3,4,5}; in-bed-but-awake is 0/2. As with everything else here, **confirm the enum against the device's iOS SDK** — Apple has *added* sleep stages over time (the core/deep/REM split arrived after the original in-bed/asleep pair), so an older image's codes are a smaller set. Other category types (mindful minutes, menstrual flow, audio-exposure events) each define their own `value` semantics — resolve per type, never assume a universal meaning for the integer.

```sql
-- Asleep windows (substitute the enumerated sleep data_type for this image)
SELECT datetime(s.start_date+978307200,'unixepoch') asleep_from,
       datetime(s.end_date  +978307200,'unixepoch') asleep_to,
       c.value AS stage
FROM samples s JOIN category_samples c ON c.data_id = s.data_id
WHERE s.data_type = /* sleep code, enumerate it */ 63
  AND c.value IN (1,3,4,5)
ORDER BY s.start_date;
```

### Metadata, correlations, and the embedded location angle

`metadata_values` (joined by `object_id`, with the key resolved through `metadata_keys.key_id`) is where samples stash their extras: `HKTimeZone`, weather/temperature/humidity at workout time, device name, the elevation gained, and sync identifiers. It is also a **secondary location source** — workout and some quantity samples carry latitude/longitude (or a weather-station location) in metadata, independent of `location_series_data` and the location daemon. Pull it like any EAV table:

```sql
SELECT mk.key, mv.string_value, mv.numerical_value,
       datetime(mv.date_value+978307200,'unixepoch') AS date_value
FROM metadata_values mv
JOIN metadata_keys  mk ON mk.ROWID = mv.key_id
WHERE mv.object_id = :data_id;
```

`correlations` groups co-measured samples into one logical reading. A **blood-pressure** entry is a correlation tying a systolic and a diastolic `quantity_samples` row; a **food** entry ties its nutrient samples. Read a correlation, not its parts, or you'll report half a blood-pressure reading.

### Deleted samples and the sync ledger

Health is a **nanosync** store — it mirrors bidirectionally to the paired Watch and (E2E) to iCloud, which means deletions must be *propagated*, not just applied locally. That propagation requirement leaves bookkeeping: deleted samples are typically recorded in a deletion ledger so peers can mirror the removal, rather than the row simply vanishing. The exact table name varies by version (inspect with `.schema` — look for a `*deleted*` or `*tombstone*`-style table and deletion markers on `objects`), so **enumerate it, don't assume it.** Two practical recovery angles regardless of the exact name:

- The deletion ledger can prove a sample *existed and was removed* (the timestamp/UUID survives even when the measurement is gone) — a tampering indicator if the deletions cluster around a window of interest.
- The `-wal`/`-shm` sidecars and the `.hfd` blob store may still hold recently-deleted rows/series not yet checkpointed or vacuumed — one more reason to copy the *whole* file set and consider [[14-deleted-data-recovery]] techniques (SQLite freelist/WAL carving) on the copy.

> 🔬 **Forensics note:** A correlation between Health and other stores is strongest when the Health *deletion* ledger shows samples removed exactly when `knowledgeC.db` shows the Health app in focus — a person actively curating their own activity record. Anti-forensic editing of Health is rare but real (faked/removed workouts in fraud and alibi cases); the ledger + provenance are how you catch it. See [[02-correlation-and-anti-forensics]].

### `data_provenances`: the device-pairing and OS-history witness

This is the table examiners forget exists, and it is often the most evidentially powerful one in the file. Every sample's `objects.provenance` points at a `data_provenances` row that records **exactly which device, app, and OS version produced it.** On iOS 18 it carries ~16 columns; the load-bearing ones:

| Column | What it proves |
|---|---|
| `origin_product_type` | The producing device's model identifier — `iPhone16,2`, `Watch7,1`, etc. **A `Watch*` value is direct proof a specific Apple Watch model was paired and contributing data.** |
| `source_version` | The iOS/watchOS version that wrote the sample — e.g. `26.5`. Across many samples this draws an **OS-upgrade timeline**. |
| `origin_build` | The exact build (`23F...`) — finer than `source_version`. |
| `source_id` | An identifier that groups samples from the same logical source/device instance. |
| `tz_name` | The IANA timezone the activity was recorded in — `America/New_York`. A *travel* signal when it changes. |
| `device_id` / origin fields | Further device identity used to disambiguate multiple watches/phones over the device's life. |

Because the table accumulates a row per (device, app, OS) combination ever seen, you can reconstruct the **device's entire pairing and upgrade history** from a single file:

```sql
-- Device + OS timeline: every (model, OS) that ever wrote Health data, with its active window
SELECT data_provenances.origin_product_type AS device,
       data_provenances.source_version      AS os_version,
       COUNT(*)                             AS samples,
       datetime(MIN(objects.creation_date)+978307200,'unixepoch') AS first_seen,
       datetime(MAX(objects.creation_date)+978307200,'unixepoch') AS last_seen
FROM objects
JOIN data_provenances ON data_provenances.ROWID = objects.provenance
GROUP BY device, os_version
ORDER BY first_seen;
```

Typical output reconstructs a story the suspect may not volunteer: an `iPhone14,2` running `17.0`→`17.5`→`18.x`, a `Watch6,2` appearing at a date that pins **when the watch was paired**, and a `Watch7,1` appearing later — a watch *upgrade*. The watch's first-seen timestamp is a hard lower bound on "this person owned and paired an Apple Watch by date X."

> 🔬 **Forensics note:** Provenance is corroboration *and* an anti-spoofing check. A `quantity_samples` step spike whose provenance is a *third-party app* (e.g. a fitness app that lets users hand-enter steps) is far weaker evidence of physical movement than the same spike sourced from `origin_product_type` = the phone's motion coprocessor or a paired Watch. Always read the value *and* its provenance together. (This also catches fabricated data: hand-injected samples carry tell-tale provenance.)

### From samples to pattern of life

The investigative payoff is turning raw samples into a **presence-and-activity timeline**:

- **Step counts** (`data_type` = steps) are interval `quantity_samples`. A non-zero step bucket places the person *physically walking* in that window — a strong rebuttal to "the phone was left at home." The phone-only path stores these in **variable-length buckets**: forensic testing on older iPhones found a most-frequent interval around 60–70 s that the algorithm stretches dynamically up to a **600 s (10-minute) maximum** during sustained activity, while newer models often coalesce a whole walk into a single entry (enumerate the actual intervals per image). Resolution is therefore coarse and non-uniform, but the *fact of movement* in the window is unambiguous.
- **Heart rate** (`quantity_samples`, count/min) from a paired Watch arrives every few seconds during workouts and periodically at rest. An elevated, *rising* HR series is exertion; resting HR samples through the night prove the watch was *worn while sleeping*. The beat-to-beat detail behind HRV/HR sits in `healthdb_secure.hfd`.
- **Workouts** (`workouts` + `workout_activities`) bound an activity in time, type, energy, and distance — and the matching `location_series_data` / `.hfd` track turns it into a **route**. A run logged 06:02–06:41 with a GPS polyline is presence-plus-location with second resolution, sourced independently of [[07-location-history]]'s caches (and therefore a cross-check on them).
- **Sleep analysis** (`category_samples`, sleep type) records in-bed / asleep / awake stages. It answers "when was this person asleep?" — directly relevant to "who was using the phone at 03:00?" If sleep says *asleep* while `knowledgeC.db` says an app was in foreground, that contradiction is itself a finding (someone else, or the subject awake).
- **ECG / irregular-rhythm / fall-detection / Vitals** events are discrete, timestamped, and (for falls/crashes) sometimes tied to a location and an emergency-call attempt — a precise incident anchor.

Each becomes one lane in a unified timeline; the real power is **correlation** — Health movement vs. `knowledgeC.db` app focus vs. [[07-location-history]] vs. [[03-powerlog-and-aggregate-dictionary]] charge/discharge. A step spike + HR climb + a workout + a CMSC location displacement at the same minute is four independent stores agreeing the person was moving. The shape you're building looks like this:

```
        06:00      06:02            06:41   06:45        07:10
Health  │··········│████ workout: run ████│············│·· steps 0 ··
HR(bpm) │ 58 58 60 │ 92 ↗ 131 ↗ 154 ↘ 120 │ 71 65 ···  │ 61 ···
knowC   │ locked   │  (screen off, in pocket)           │ Mail inFocus
loc     │ home     │  polyline ───────────► park loop    │ home
                    └─ four stores agree: PERSON MOVING ─┘     └ back, sedentary
```

Read top-to-bottom at any minute and the stores either corroborate or contradict — and a contradiction (Health says asleep while an app is in foreground) is itself the finding. See [[01-building-a-unified-timeline]] and [[02-correlation-and-anti-forensics]].

> 🔬 **Forensics note (Watch-sourced uniqueness):** Samples whose provenance is the Watch are *only consolidated here.* The Watch keeps its own local store, but you rarely acquire the watch; the phone's `healthdb_secure.sqlite` is the practical single copy of the watch's contribution. That makes this file evidence about a device you may never image — and makes the Class-B/lock caveat doubly painful, because losing the phone to BFU, or just to an extended screen-lock, also loses your only copy of the watch's data.

## Hands-on

There is no on-device shell; everything runs on your Mac against a copy. **Copy before you query — always.** A plain `sqlite3 ... "SELECT ..."` opens the DB read-write, may checkpoint the `-wal`, and spawns `-shm` — mutating evidence. Pull the whole file set together.

```bash
# 1) Stage a forensic copy — the main DB *and* its sidecars + the .hfd, together.
#    (Copying the .sqlite without its -wal can silently drop the most recent samples.)
SRC=/path/to/extraction/private/var/mobile/Library/Health
DST=/tmp/health_copy && mkdir -p "$DST"
cp "$SRC"/healthdb.sqlite* "$DST"/
cp "$SRC"/healthdb_secure.sqlite* "$DST"/
cp "$SRC"/healthdb_secure.hfd* "$DST"/ 2>/dev/null

# 2) Hash for chain of custody before touching anything.
shasum -a 256 "$DST"/healthdb_secure.sqlite*

# 3) Open READ-ONLY so even an accident can't write. Note the immutable URI.
sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" '.mode column' '.headers on'
```

Enumerate the schema first — never assume table/column names match a blog (they drift by version):

```bash
sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" '.schema samples'
sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" '.tables'
```

Profile what types exist and how much (this *is* triage — it tells you whether a watch was involved at all):

```bash
sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" "
SELECT data_type, COUNT(*) n,
       datetime(MIN(start_date)+978307200,'unixepoch') first,
       datetime(MAX(start_date)+978307200,'unixepoch') last
FROM samples GROUP BY data_type ORDER BY n DESC;"
```

Steps in a target window (substitute the *enumerated* step code for your image, e.g. 7):

```bash
sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" "
SELECT datetime(s.start_date+978307200,'unixepoch') start_utc,
       datetime(s.end_date  +978307200,'unixepoch') end_utc,
       q.quantity steps
FROM samples s JOIN quantity_samples q ON q.data_id=s.data_id
WHERE s.data_type = 7
  AND s.start_date BETWEEN (strftime('%s','2026-05-01 09:00:00')-978307200)
                       AND (strftime('%s','2026-05-01 10:00:00')-978307200)
ORDER BY s.start_date;"
```

Device + OS history (the provenance query from Concepts) and workouts:

```bash
sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" "
SELECT dp.origin_product_type device, dp.source_version os, COUNT(*) n,
       datetime(MIN(o.creation_date)+978307200,'unixepoch') first_seen,
       datetime(MAX(o.creation_date)+978307200,'unixepoch') last_seen
FROM objects o JOIN data_provenances dp ON dp.ROWID=o.provenance
GROUP BY device, os ORDER BY first_seen;"

sqlite3 "file:$DST/healthdb_secure.sqlite?immutable=1" "
SELECT datetime(s.start_date+978307200,'unixepoch') start_utc,
       w.duration, w.total_distance, w.total_energy_burned
FROM samples s JOIN workouts w ON w.data_id=s.data_id
ORDER BY s.start_date DESC LIMIT 25;"
```

Let purpose-built tooling carry the version-resolution burden once you understand the joins:

```bash
# iLEAPP — has Health plugins that resolve types, units, and provenance into HTML/CSV/timeline.
python3 ileapp.py -t fs -i /path/to/extraction -o /tmp/ileapp_out

# kacos2000's curated query (healthdb_secure.sql) — run in DB Browser for SQLite against the COPY.
#   github.com/kacos2000/Queries  → healthdb_secure.sql

# christophhagen/HealthDB — Swift package documenting the schema + decoding the .hfd series.
```

> ⚠️ **ADVANCED:** Pulling Health off a *live* device is device-bound and out of scope here (no device on this course), but for the record: it requires the device **unlocked (or freshly locked, inside the Class-B window)** and either an encrypted backup (`idevicebackup2 backup --full`, with a backup password set, then decrypt) or a full-file-system exploit. Never attempt it against a device that has rebooted to BFU — the class keys are gone and you will get ciphertext — and don't let it sit locked, which alone sheds the Class-B samples. Document lock state and time-since-unlock at every step.

## 🧪 Labs

> All labs are **device-free**. The phone-resident, Class-B, Watch-fed reality of this store cannot be reproduced on a Mac, so the high-fidelity labs use a **public sample image** and the Simulator lab is explicitly a *fidelity-gap* exercise. The Simulator runs macOS HealthKit: **no SEP, no Data-Protection-at-rest, no `biomed`/motion-coprocessor, no paired Watch, no `.hfd` per-second series** — so it teaches schema shape only, never lock-state or provenance behaviour.

### Lab 1 — Schema-first triage on a public sample image (substrate: public forensic image)

Use a known iOS reference image with Health data (Josh Hickman's iOS images on thebinaryhick.blog / Digital Corpora; or the iLEAPP test data).

1. Locate `.../private/var/mobile/Library/Health/` in the extraction. Stage a copy of the whole file set (the `cp` block above). Hash it.
2. Open `healthdb_secure.sqlite` **read-only** (`?immutable=1`). Run `.schema samples`, `.schema quantity_samples`, `.schema data_provenances`. Write down the *actual* column names — compare them to this lesson and note any drift.
3. Run the `data_type` profile query. **Do not** trust the integer table in this lesson — record which codes are present in *this* image and how many of each.
4. Resolve at least three of those codes to meaning (steps, distance, heart rate) by sampling rows and reasoning from the units in `unit_strings`, not by pasting a number table.
   - *Fidelity caveat:* a real image carries the protection-class / lock-state story you can't see post-decryption; note in your worksheet whether the extraction tool reported the device as unlocked / AFU and the time-since-unlock.

### Lab 2 — Device-pairing & OS-upgrade timeline from provenance (substrate: public forensic image)

1. On the same copy, run the `objects ⨝ data_provenances` device+OS history query.
2. Identify every `origin_product_type`. Map the model identifiers to marketing names (e.g. `Watch6,2` → a specific Apple Watch) using theapplewiki.com — **don't** hardcode a mapping from memory.
3. From `first_seen`, state the date a **paired Apple Watch first contributed data** — your lower bound on Watch ownership/pairing.
4. From `source_version` over time, draw the iOS-upgrade timeline. Cross-check it against an OS-history signal from another store if the image has one (e.g. install/OTA artifacts).
   - *Fidelity caveat:* provenance richness depends on real multi-device use; a single-device test image shows the mechanism but a thin timeline.

### Lab 3 — Build a presence/activity lane and correlate (substrate: public forensic image)

1. Extract three lanes into CSV from the copy: (a) step buckets, (b) heart-rate samples, (c) `workouts` rows with start/end.
2. Pick one workout. Show that step counts rise and heart rate climbs across its window — three stores agreeing on "moving."
3. If the image has sleep-analysis (`category_samples`), extract the asleep windows and look for any *contradiction*: an app in foreground in `knowledgeC.db` (from [[01-knowledgec-db-deep-dive]]) during a window Health calls "asleep." Document the contradiction as a finding.
4. Merge the lanes by timestamp into one timeline; this is the seed of [[01-building-a-unified-timeline]].
   - *Fidelity caveat:* the per-second GPS/HR detail lives in `.hfd`; plain SQLite gives you the aggregate samples. Decoding `.hfd` (christophhagen/HealthDB) is a stretch goal.

### Lab 4 — Feel the fidelity gap on the Simulator (substrate: Xcode Simulator)

1. Boot a Simulator (`xcrun simctl boot "iPhone 17"`). HealthKit on the Simulator only contains what an app writes via `HKHealthStore` (the Health app on Simulator can also seed a little). There is **no** motion-coprocessor stream and **no** Watch.
2. Find whatever HealthKit store the Simulator created — *don't assume the device path*; search for it:
   ```bash
   UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
   find ~/Library/Developer/CoreSimulator/Devices/$UDID/data -iname 'healthdb*' 2>/dev/null
   ```
   (The Simulator does **not** reproduce `/private/var/mobile/Library/Health/`; verify where — if anywhere — it lands on your Xcode version.)
3. If you find a store, open it read-only and run the same `.schema` / `data_type` profile. Contrast with Lab 1: note the **absent** `data_provenances` richness (no Watch model, no OS-upgrade chain), the **absent** `.hfd` per-second series, and the fact that the file sits **unencrypted** on your Mac — the exact opposite of the Class-B device reality.
4. Conclusion to write down: the Simulator teaches *table joins*, and *nothing* about lock state, provenance, or protection class. Those are device-only and must be learned from sample images.

## Pitfalls & gotchas

- **The passwordless-backup trap.** A logical backup with *no* backup password silently **omits Health entirely** (and the Keychain). Examiners pull a quick `idevicebackup2 backup`, see no Health, and conclude "the user had Health off." Wrong: set a backup password and re-pull, or do FFS. Absence of Health in a passwordless backup is meaningless.
- **BFU = nothing, the 10-minute lock window is the quiet killer, and the 72-hour clock is silent.** The Health *samples* (Class B) seal back to ciphertext ~10 minutes after the screen locks — so a phone that merely sat locked on the bench can lose `healthdb_secure.sqlite` while ordinary Class-C stores stay readable. A device that rebooted (manually, low battery, or the ~72 h inactivity reboot) is fully back at BFU and even a perfect FFS yields nothing. None of this leaves an obvious banner — keep the phone **awake and unlocked**, check uptime/boot artifacts and your seizure log, and record time-since-unlock.
- **Hardcoding `data_type` integers.** The single most common reporting error. The internal `HKObjectType` ordinals shift between iOS majors; a number table from a 2021 blog can mislabel samples on a 2026 image. Enumerate per-image and resolve against the device's own registry or the matching SDK. (`workout_activities.activity_type` is the stabler public enum, but verify it too.)
- **`localtime` lies.** `datetime(..., 'unixepoch', 'localtime')` renders in *your* timezone, not the subject's. Use UTC in the query and resolve the subject's local time from `data_provenances.tz_name` / the per-sample `HKTimeZone` metadata. A timezone error of hours destroys an alibi analysis.
- **Forgetting the `-wal` and `.hfd`.** Copy `healthdb_secure.sqlite` alone and you may miss the most recent (uncheckpointed) samples in `-wal`, and you'll have *no* per-second HR/GPS series without `.hfd`. Stage the whole file set, hash it, query the copy.
- **Querying the live/original file.** SQLite write-locks and checkpoints on open. Open `?immutable=1` against a copy. Treat the original as evidence you never touch.
- **Self-reported ≠ sensor-measured.** A step/weight/HR sample whose `data_provenances` source is a third-party or manual-entry app is *user-asserted*, not sensor-measured. Read value and provenance together before testifying to physical activity. Fabricated samples are detectable precisely here.
- **Distance/step aggregation hides resolution.** The phone-only path buckets locomotion into variable intervals (research on older iPhones: ~60–70 s typical, stretching up to a 600 s / 10-min maximum during sustained activity; newer models may log a whole session as one entry). You can prove "moving in this window," not "stepped at exactly 09:14:32." Don't over-claim precision the store doesn't have.
- **Sleep "asleep" is an inference, not a sensor of consciousness.** A sleep-analysis sample reflects the device's bedtime/HR/motion model, not a guarantee the person was unconscious. Use it as corroboration, not proof of state.

## Key takeaways

- `healthdb_secure.sqlite` under `/private/var/mobile/Library/Health/` is a per-second physiological + locomotion log — steps, heart rate, workouts (with GPS routes), sleep — and one of the most under-mined pattern-of-life stores on iOS.
- The samples store is **Data-Protection class Protected Unless Open (`NSFileProtectionCompleteUnlessOpen`, Class B): readable only while unlocked or within ~10 min of locking**; the metadata DB is Class C (AFU-resident). A BFU device — including one that hit the ~72 h inactivity reboot — yields *nothing*, and even an AFU device sheds the samples once it has been locked past the window. Keep seized Health-bearing phones **awake and unlocked**; record lock state and time-since-unlock.
- The schema radiates from **`samples`** (keyed `data_id`); join out to `quantity_samples`, `category_samples`, `workouts`, and via `objects.provenance` to `data_provenances`. Metadata hangs off `metadata_values`/`metadata_keys`. The `.hfd` file holds the per-second HR/GPS blobs.
- **`data_provenances` is the device-pairing + OS-history witness:** `origin_product_type` proves *which* phone/Watch produced each sample (a `Watch*` value = a paired watch and *when*), and `source_version` reconstructs the OS-upgrade timeline.
- All timestamps are **Mac Absolute Time** (+978307200 → Unix); resolve subject-local time from `tz_name`, never your workstation's `localtime`.
- **Never hardcode `data_type` integers** — they shift across iOS versions. Enumerate the codes in *this* image and resolve them against the device's registry or the matching SDK.
- Acquisition is constrained: FFS on an AFU device, an **encrypted** backup (password-protected), or E2E-encrypted iCloud — a *passwordless* backup omits Health entirely.
- Watch-sourced samples are consolidated *only* on the phone; combined with `knowledgeC.db`, location, and PowerLog they corroborate a minute-by-minute presence/activity timeline.

## Terms introduced

| Term | Definition |
|---|---|
| `healthdb_secure.sqlite` | The protected primary HealthKit store (samples, workouts, heart rate, provenance); Data-Protection class Protected Unless Open (Class B). |
| `healthdb.sqlite` | The companion metadata DB (sources and type registry) referenced by the secure store. |
| `healthdb_secure.hfd` | "High-frequency data" binary container for per-second series (heart-rate beat series, workout GPS track, HRV). |
| `samples` | The hub table; one row per sample with `data_id`, `start_date`, `end_date`, and `data_type`. |
| `quantity_samples` | Numeric values (steps, distance, heart rate, energy) keyed to `samples` by `data_id`. |
| `category_samples` | Enumerated values (sleep stages, mindful minutes, etc.) keyed to `samples` by `data_id`. |
| `workouts` / `workout_activities` | Per-workout summary (duration, energy, distance) and its activity segments; `activity_type` is the `HKWorkoutActivityType` enum. |
| `objects` | Per-sample identity/provenance row; `objects.provenance` → `data_provenances.ROWID`. |
| `data_provenances` | Per-source record: `origin_product_type` (device model), `source_version` (OS), `tz_name` (timezone) — the device-pairing/OS-history witness. |
| `data_type` | Integer `HKObjectType` ordinal in `samples`; **unstable across iOS versions — enumerate, don't hardcode.** |
| Mac Absolute Time | Timestamp epoch 2001-01-01 UTC; add 978307200 to convert to Unix. |
| NSFileProtectionCompleteUnlessOpen (Class B) | "Protected Unless Open" Data-Protection class of the Health samples: writable while locked, but the read (private) key is relinquished ~10 min after lock — the reason `healthdb_secure.sqlite` needs an unlocked or freshly-locked device. |
| AFU / BFU | After-First-Unlock / Before-First-Unlock device states; with the Health samples at Class B, a BFU device yields nothing and an AFU device sheds the samples once locked past the ~10-min window. |

## Further reading

- Apple Developer — HealthKit (`HKObjectType`, `HKQuantitySample`, `HKWorkout`, `HKWorkoutActivityType`, Metadata Keys); Apple Platform Security guide (Data Protection classes, Health/iCloud E2E encryption).
- DFIR Review — "Enriching Investigations with Apple Watch Data Through the `healthdb_secure.sqlite` Database" (dfir.pubpub.org).
- DFRWS / ScienceDirect — "The provenance of Apple Health data: A timeline of update history"; "Interpreting the location data extracted from the Apple Health database"; "The iPhone Health App from a forensic perspective: can steps and distances registered during walking and running be used as digital evidence?" (step/distance aggregation intervals).
- The Metadata Perspective — "Beyond the Logs: Using the Health App to Uncover Device Model and OS History" (data_provenances), and "Empirical Assessment of Apple Health Activity Data" (granularity/aggregation), metadataperspective.com.
- Cellebrite — "How Health App Data Improves Location Accuracy and Activity Identification for Investigations."
- kacos2000/Queries — `healthdb_secure.sql` (curated examiner query); christophhagen/HealthDB (schema + `.hfd` decoding, Swift).
- iLEAPP (Alexis Brignoni) — Health plugins; Sarah Edwards (mac4n6.com) — pattern-of-life methodology and timestamp handling.
- theapplewiki.com — `origin_product_type` model-identifier → marketing-name mapping.
- ElcomSoft blog — "Securing and Extracting Health Data: Apple Health vs. Google Fit" (backup-password requirement, acquisition routes).

---
*Related lessons: [[01-knowledgec-db-deep-dive]] | [[07-location-history]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[01-building-a-unified-timeline]] | [[00-the-ios-timestamp-zoo]] | [[02-correlation-and-anti-forensics]] | [[14-deleted-data-recovery]]*
