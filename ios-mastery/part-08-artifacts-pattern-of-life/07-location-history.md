---
title: "Location history"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 07
est_time: "50 min read + 25 min labs"
prerequisites: [knowledgec-db-deep-dive, photos-and-the-camera-roll]
tags: [ios, forensics, location, routined, significant-locations, dfir]
last_reviewed: 2026-06-26
---

# Location history

> **In one sentence:** An iPhone is a self-surveilling movement recorder — `routined`'s Core Data stores log not just *where* the device was but *how fast it was moving* at each fix, and fusing those points with learned Significant Locations, the `locationd` Wi-Fi/cell caches, Maps route requests, and photo EXIF turns the phone into the single most decisive location witness in a case.

## Why this matters

Location is the artifact category that puts a defendant at a scene, refutes an alibi, or reconstructs a kidnapping route — and the iPhone keeps far richer location data than its owner imagines. The headline is `com.apple.routined`: a background daemon that continuously fixes the device's position from GNSS, Wi-Fi, and cell, and stores each fix **with the device's instantaneous speed and heading**. A `ZSPEED` of 31 m/s (≈70 mph) on a residential street at 02:14 is corroboration or refutation that no witness statement can match. Significant Locations (the learned "home" and "work" clusters) are a separate, longer-lived store that is **excluded from iTunes/iCloud backups** — you only get them from a full file-system extraction, which makes the *acquisition method* part of the evidentiary story. This lesson maps the entire iOS location zoo: every store, its on-disk path, its schema, its epoch, its Data-Protection class, and how to fuse them into one defensible timeline. It builds directly on [[01-knowledgec-db-deep-dive]] (the Core Data / Mac-Absolute-Time idiom you already know) and [[06-photos-and-the-camera-roll]] (EXIF GPS, your independent corroboration source).

## Concepts

### The iOS location zoo: one phenomenon, many stores

There is no single "location database." Location is recorded redundantly by several subsystems that each answer a different question, at a different cadence, with a different retention and a different Data-Protection class. Internalize the map before touching any one store:

```
                         ┌─────────────────────────────────────────────┐
   GNSS / Wi-Fi / cell ──▶  locationd (daemon, runs as root)            │
   motion coprocessor ──▶   - serves CLLocation to clients              │
                         │   - crowd-sourced geo cache (cache_encrypted*)│
                         └───────────────┬─────────────────────────────┘
                                         │ feeds
                ┌────────────────────────▼───────────────────────────┐
                │  routined (CoreRoutine / CoreDuet learning daemon)  │
                │  /var/mobile/Library/Caches/com.apple.routined/     │
                │   • Cache.sqlite   → raw fixes + SPEED (short-lived) │
                │   • Local.sqlite   → learned visits / LOIs / vehicle │
                │   • Cloud-V2.sqlite→ Significant Locations (synced)  │
                └────────────────────────┬───────────────────────────┘
                                         │ consumed by
        ┌────────────────┬──────────────┼───────────────┬────────────────┐
        ▼                ▼              ▼                ▼                ▼
   Significant       Siri/Maps      knowledgeC        Photos          Weather/
   Locations UI      predictions    /Biome streams    "Places"        widgets
```

Two daemons matter most. **`locationd`** is the low-level provider — it computes the actual `CLLocation` and maintains an on-disk cache of Wi-Fi-AP and cell-tower → coordinate mappings so the device can geolocate without a network round-trip. **`routined`** sits above it: it is the *pattern-of-life learner* (part of Apple's CoreDuet / CoreRoutine on-device intelligence stack, the same family that produces `knowledgeC`/Biome). `routined` samples `locationd`, persists the raw fixes, and over time clusters them into "Significant Locations" — your home, your work, your gym — and detects events like parking your car.

> 🖥️ **macOS contrast:** Your Mac runs `locationd` too, and even keeps a thin Significant Locations list (System Settings → Privacy & Security → Location Services → System Services → Significant Locations). But a laptop is mostly stationary, has no always-on GNSS, no cellular baseband, and no motion coprocessor producing a continuous velocity stream — so its `routined` data is sparse and there is **no `ZSPEED` story**. The macOS location caches you parsed in `macos-mastery` (`/var/db/locationd/clients.plist`, the knowledgeC location columns) tell you *who asked for location*; the iPhone tells you *where the body was and how fast it was moving*. The phone is the location witness; the Mac is a footnote.

### `routined` — the Core Data spine

Everything `routined` writes is a **Core Data SQLite store**: `Z`-prefixed tables, `Z_PK` primary keys, a `Z_PRIMARYKEY`/`Z_METADATA` housekeeping pair, and `NSDate` columns stored as doubles in **Mac Absolute Time** (seconds since `2001-01-01 00:00:00 UTC`). You convert to Unix by adding `978307200` — exactly the idiom from [[01-knowledgec-db-deep-dive]]. The directory:

```
/private/var/mobile/Library/Caches/com.apple.routined/
├── Cache.sqlite          (+ -wal, -shm)   raw location fixes, high-frequency
├── Local.sqlite          (+ -wal, -shm)   learned visits, LOIs, parked vehicle
├── Cloud-V2.sqlite       (+ -wal, -shm)   Significant Locations (iCloud-synced)
└── (historical: Cloud.sqlite pre-iOS 13; CoreRoutine.sqlite on some builds)
```

> 🔬 **Forensics note:** Always grab the `-wal` and `-shm` sidecars with each `.sqlite`. On a live or AFU device the most recent fixes — often the ones you care about — live in the write-ahead log and have **not** yet been checkpointed into the main file. Copy the trio together; never run a bare `sqlite3` open against the original (even a `SELECT` checkpoints the WAL and mutates the evidence). Hash all three before and after.

Because these are Core Data, the table inventory is discoverable, not memorized. `Z_PRIMARYKEY` maps each entity name to its `Z_ENT` integer and gives a live row count; that is your first orientation in an unfamiliar image:

```sql
SELECT Z_NAME, Z_ENT, Z_SUPER FROM Z_PRIMARYKEY ORDER BY Z_NAME;   -- entity catalog
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'ZRT%';  -- routined tables
```

`Z_NAME` values strip the `Z…MO` Objective-C class decoration (Core Data prepends `Z` and appends `MO`/managed-object), so `RTLearnedVisit` in `Z_PRIMARYKEY` is the `ZRTLEARNEDVISITMO` table. Run this *first* on every new image — it tells you which of the version-variable tables actually exist before you write a query against a column that moved.

### `Cache.sqlite` → `ZRTCLLOCATIONMO`: the speed table

This is the crown jewel. `ZRTCLLOCATIONMO` ("RouTined CLLocation Managed Object") is a near-verbatim serialization of the `CLLocation` objects `locationd` handed to `routined`. Each row is one positional fix with the full kinematic state:

| Column | Meaning | Forensic weight |
|---|---|---|
| `ZTIMESTAMP` | Fix time (Mac Absolute Time double) | the anchor |
| `ZLATITUDE`, `ZLONGITUDE` | WGS-84 coordinate | the position |
| `ZALTITUDE` | metres above ellipsoid | floor/elevation hints |
| `ZSPEED` | **instantaneous speed, m/s** (−1 = invalid) | alibi maker/breaker |
| `ZCOURSE` | heading, degrees from true north (−1 = invalid) | direction of travel |
| `ZHORIZONTALACCURACY` | radius of confidence, metres | how much to trust the point |
| `ZVERTICALACCURACY` | altitude confidence, metres | filter bad fixes |
| `Z_PK` | row id | join/order key |

The fixes arrive in **bursts** whenever the device is moving or an app holds a location session — controlled testing has logged 41 fixes inside a 40-second window — so a single drive can leave hundreds of densely-spaced points. Retention is short — **roughly a week** (historically ~7 days; it varies by usage and OS version, so verify against the image's own oldest `ZTIMESTAMP`). That short window is exactly why you acquire fast and why `Cache.sqlite` is so often the difference-maker for a *recent* event.

The canonical query (epoch-converted, with speed unit conversions) — this is the APOLLO `routined_cache_zrtcllocationmo` module distilled:

```sql
SELECT
  datetime(ZTIMESTAMP + 978307200, 'unixepoch')          AS fix_utc,
  ZLATITUDE                                              AS lat,
  ZLONGITUDE                                             AS lon,
  ZALTITUDE                                              AS alt_m,
  ZSPEED                                                 AS speed_mps,
  round(ZSPEED * 2.23694, 1)                             AS speed_mph,
  round(ZSPEED * 3.6, 1)                                 AS speed_kmh,
  ZCOURSE                                                AS heading_deg,
  ZHORIZONTALACCURACY                                    AS h_acc_m,
  ZVERTICALACCURACY                                      AS v_acc_m,
  Z_PK
FROM ZRTCLLOCATIONMO
WHERE ZSPEED >= 0            -- drop invalid speed sentinels
ORDER BY ZTIMESTAMP;
```

> 🔬 **Forensics note:** `ZSPEED` is computed by `locationd` from the Doppler shift of GNSS carrier signals, not by differencing successive lat/lons — so it is an *independent* measurement of velocity, not a derivative of the positions in the same table. That independence is what makes it powerful in court: it has corroborated speeding-related vehicular cases (a phone clocking 31 m/s when the driver claimed they were stopped) and refuted others. Two discipline rules from controlled testing: (1) always filter `ZSPEED >= 0` — `−1.0` is CoreLocation's "speed unavailable" sentinel, not a real reading; (2) **only trust the speed when `ZHORIZONTALACCURACY` ≤ ~65 m** — published validation work treats 65 m as the cutoff above which the speed reading degrades. A `ZHORIZONTALACCURACY` of 1500 m is a Wi-Fi/cell estimate you should not place on a specific street, let alone quote a speed from.

#### Reverse-geocode protobuf BLOBs

Older `routined`/Maps rows often embedded the human-readable street address as a serialized **protobuf BLOB** rather than plain text (the `ZRTMAPITEMMO` address payloads, the historical `ZADDRESS`/place columns). Apple has progressively stripped or relocated these reverse-geocode BLOBs in newer iOS releases, so on a 2026-era image you may find the *coordinate* present but the *address* either gone or moved. When a BLOB is present, decode it (Sarah Edwards' `sqlite_miner` protobuf branch, `protobuf-inspector`, or `protoc --decode_raw`) — never assume a column is "empty" just because `sqlite3` prints a binary smear. A reverse-geocoded "123 Elm St" inside a BLOB is the difference between a lat/lon pair and a named address in your report.

### `Local.sqlite` and `Cloud-V2.sqlite` → Significant Locations

`routined` clusters the raw fixes into higher-order semantic objects. These live in `Local.sqlite` (device-local) and `Cloud-V2.sqlite` (the iCloud-synced superset — renamed from `Cloud.sqlite` at iOS 13). The key tables (Core Data, same epoch):

| Table | Records |
|---|---|
| `ZRTLEARNEDVISITMO` | A *visit*: the device dwelled at a place. Entry/exit/creation/expiration dates, lat/lon, plus confidence and uncertainty fields. |
| `ZRTLEARNEDLOCATIONOFINTERESTMO` | A *Location of Interest* (LOI) — a learned recurring place, i.e. a row in the user-facing **Significant Locations** list (home, work, the gym). |
| `ZRTMAPITEMMO` | The named/reverse-geocoded place (street address, POI name) linked to LOIs and visits. |
| `ZRTLEARNEDVEHICLELOCATIONMO` *(vehicle/parked family)* | The "parked car" drop — see below. |

A visit gives you a dwell interval (entry → exit), which is qualitatively different from `Cache.sqlite`'s instantaneous fixes: it answers "the phone was at 123 Elm St from 18:42 to 06:15," which is the alibi-relevant unit. The LOI + `ZRTMAPITEMMO` join is what lets you write "home = 123 Elm St, work = 400 Industrial Pkwy" with confidence values attached.

```sql
-- Significant-Locations visits, newest first (Local.sqlite or Cloud-V2.sqlite)
SELECT
  datetime(ZENTRYDATE      + 978307200, 'unixepoch') AS entry_utc,
  datetime(ZEXITDATE       + 978307200, 'unixepoch') AS exit_utc,
  datetime(ZCREATIONDATE   + 978307200, 'unixepoch') AS created_utc,
  ZLATITUDE  AS lat,
  ZLONGITUDE AS lon
FROM ZRTLEARNEDVISITMO
ORDER BY ZENTRYDATE DESC;
```

To put a *name* on a learned place, join the LOI to its reverse-geocoded map item. The exact relationship column changes by version, so confirm it from the schema before relying on this shape:

```sql
-- Name the Significant Locations (LOIs) via their linked map item.
-- Inspect the FK first:  .schema ZRTLEARNEDLOCATIONOFINTERESTMO  /  .schema ZRTMAPITEMMO
SELECT
  loi.Z_PK                                          AS loi_id,
  loi.ZLATITUDE                                     AS lat,
  loi.ZLONGITUDE                                    AS lon,
  mi.ZNAME                                          AS place_name,    -- verify column
  datetime(loi.ZCREATIONDATE + 978307200,'unixepoch') AS first_seen_utc
FROM ZRTLEARNEDLOCATIONOFINTERESTMO loi
LEFT JOIN ZRTMAPITEMMO mi ON mi.Z_PK = loi.ZMAPITEM   -- FK name varies by iOS; verify
ORDER BY loi.ZCREATIONDATE;
```

> ⚠️ **Exact column names in `Local.sqlite`/`Cloud-V2.sqlite` drift between iOS releases** (Apple re-shaped these tables at iOS 11→12, again at 13, and has stripped/relocated reverse-geocode protobuf BLOBs in later versions). Treat the column list above as the *durable shape*, not gospel: dump the live schema first with `.schema ZRTLEARNEDVISITMO` and adapt. Let iLEAPP/APOLLO carry the version-specific mapping where you can — but read their query files so you know what they assumed.

> 🔬 **Forensics note:** Significant Locations are **not in an iTunes/Finder backup and not in an unencrypted iCloud backup** — they require a full file-system extraction (or, where End-to-End-encrypted iCloud sync is in play, the account credentials plus a cloud-acquisition path). This is a recurring exam trap: a logical/backup acquisition will show you `Cache.sqlite`-style data sometimes but will **silently lack** the learned home/work clusters. If your report claims "no Significant Locations were present," be sure that is a true negative and not an artifact of the acquisition class. See [[01-the-acquisition-taxonomy]] and [[02-bfu-vs-afu-and-data-protection-classes]].

### The parked-car artifact

When you disconnect from your car's Bluetooth or CarPlay while moving, Maps drops a "parked location" marker so you can find the car later. That convenience is a forensic gift: it records a precise coordinate and timestamp at the moment the device *left a vehicle*. `routined` persists the current and historical parked locations in `Local.sqlite` (APOLLO exposes them as the `routined_local_vehicle_parked` and `routined_local_vehicle_parked_history` modules; the underlying table is in the learned-vehicle family — confirm its exact name in your image's schema). A parked-car drop places the suspect at a coordinate, on foot, at a known minute — and CarPlay/Bluetooth pairing names in the row tie the event to a specific vehicle.

```sql
-- Parked-vehicle events (Local.sqlite); confirm the table name via Z_PRIMARYKEY first.
-- APOLLO exposes these as routined_local_vehicle_parked[_history].
SELECT
  datetime(ZDATE + 978307200, 'unixepoch') AS parked_utc,
  ZLATITUDE  AS lat,
  ZLONGITUDE AS lon
FROM ZRTLEARNEDVEHICLELOCATIONMO          -- name varies by iOS; verify
ORDER BY ZDATE DESC;
```

> 🔬 **Forensics note:** CarPlay sessions and vehicle Bluetooth associations leave their own corroborating traces beyond the parked-car drop — pairing records in the Bluetooth stores, and CarPlay app-usage in `knowledgeC`/Biome — that bracket "the device was in *this* car from time T1 to T2." Cross-reference the parked-car coordinate/time against those: a parked drop at 14:35 should sit at the tail of a CarPlay session that ended ~14:35. A mismatch (a parked drop with no preceding drive in `Cache.sqlite`) is worth explaining.

### `locationd` — the low-level geo caches

Below `routined`, `locationd` keeps its own caches so the device can resolve a Wi-Fi BSSID or cell tower to coordinates offline. These live under **root's** home, not mobile's:

```
/private/var/root/Library/Caches/locationd/
├── cache_encryptedB.db     Wi-Fi AP + cell-tower → location cache (crowd-sourced)
├── cache_encryptedA.db     (same family; which DB holds what varies by iOS version)
├── cache_encryptedC.db     Motion history (added around iOS 18)
└── (historical: consolidated.db — the 2011 "locationgate" file)
```

Despite the `*_encrypted*` names — a legacy convention — on a **decrypted full file-system image these read as ordinary SQLite**. `cache_encryptedB.db` is the modern descendant of the infamous `consolidated.db` that triggered the 2011 "your iPhone tracks you" press cycle. It does not log *your* movement directly; it caches the *observed* Wi-Fi APs and cell towers (with their estimated coordinates and observation timestamps) the device saw. That is still powerful: it independently places the device within range of specific, geolocatable infrastructure at specific times — corroboration that does not depend on `routined` having a clean GNSS fix.

Unlike `routined`'s Core Data stores, these are **plain relational tables**, not `Z`-prefixed Core Data. The table set varies by iOS version but has historically included a family per radio technology plus a "harvest" twin for each:

| Table | Holds |
|---|---|
| `CellLocation` / `LteCellLocation` / `CdmaCellLocation` | Cell tower (MCC/MNC/LAC/CI etc.) → estimated coordinate + timestamp |
| `WifiLocation` | Wi-Fi BSSID (MAC) → estimated coordinate + timestamp |
| `*Harvest` (e.g. `CellLocationHarvest`, `WifiLocationHarvest`) | Locally observed/crowd-source-bound observations awaiting upload |

The distinction matters: the non-harvest tables are the *download* cache (Apple told the device where these towers/APs are), while the `*Harvest` tables are the device's *own* observations — the latter is the stronger "this phone personally saw BSSID X here at time T" claim. Verify the exact table names in your image (`.tables` then `.schema`); Sarah Edwards' `Mac-Locations-Scraper` and iLEAPP's `locationd` modules carry the version-aware mappings.

> 🔬 **Forensics note:** `routined` *also* reads a `cache_encryptedB.db`, but it is a **different file in a different directory** (`com.apple.routined/` vs `locationd/`) with different contents. Don't conflate them in your notes. And because the `locationd` caches sit under `/private/var/root/`, they are **root-owned and only present in a full file-system extraction** — a logical/backup acquisition never sees them.

### Apple Maps history

Maps records both *intent* (what you searched for / where you asked to navigate) and the *route*. The store has migrated repeatedly, which is itself a versioning landmine:

| Era | Artifact | Notes |
|---|---|---|
| iOS 7 and earlier | `History.mapsdata` | legacy; only survives as a leftover after upgrade |
| iOS 8–11 | `GeoHistory.mapsdata` | on-device search/route history |
| iOS 12 | (moved to iCloud) | sparse on-device |
| iOS 13+ / 14+ | `MapsSync_0.0.1` | Core Data SQLite, the current store |

The modern store:

```
/private/var/mobile/Containers/Shared/AppGroup/<GUID>/Library/Maps/MapsSync_0.0.1
```

Its `ZHISTORYITEM` table holds search and navigation history; the route detail — **start and destination coordinates** — is serialized as a **protobuf BLOB in the `ZROUTEREQUESTSTORAGE` column**, not as plain columns. You must extract and decode the protobuf (Sarah Edwards' `sqlite_miner`/protobuf work, or `protobuf-inspector`) to recover the journey endpoints. Expect a shallow history (testing has shown the store retaining only on the order of the last ~15 items), so Maps history is *intent corroboration*, not a complete travel log.

> 🔬 **Forensics note:** Maps "intent" is evidentially distinct from `routined` "presence." A `MapsSync` search for a victim's home address, or a navigation request *to* a crime scene, shows premeditation/knowledge even if the device's own GNSS track is missing. Pair the two: Maps says "the user asked how to get to X at 14:03"; `routined` `ZRTCLLOCATIONMO` says "the device was moving along that route at 50 mph from 14:10–14:35"; the `ZRTLEARNEDVISITMO` says "the device then dwelled at X from 14:40 to 15:20."

### Other location-bearing stores (the corroboration mesh)

No location finding should rest on a single store. The fusion sources, each covered elsewhere:

- **Photo EXIF GPS** — every camera-roll asset can carry `{GPSLatitude, GPSLongitude, GPSDateStamp}`; `Photos.sqlite` also stores reverse-geocoded place names and the asset's own creation time. Independent of `routined`, and far harder for a user to scrub silently. See [[06-photos-and-the-camera-roll]].
- **knowledgeC / Biome streams** — `knowledgeC.db` and the Biome SEGB streams carry app-usage and some location-tagged activity (and Biome has dedicated location/visit streams in the iOS 17+ format). See [[01-knowledgec-db-deep-dive]] and [[02-biome-and-segb-streams]].
- **Wi-Fi joins** — the known-networks store records when the device associated to named SSIDs; a join to "Marriott_Lobby" is a geolocation. (Path and format covered under networking — verify per OS version.)
- **App-specific location** — fitness apps, Find My, ride-share, and dating apps keep their own GPS tracks in their containers. See [[11-third-party-app-methodology]] and [[05-find-my-and-the-ble-mesh]].

A correctly fused window reads like this — one UTC-sorted table, each row tagged with its source store, so corroboration (and gaps) are visible at a glance:

```
UTC (Z)              SOURCE                       EVENT / VALUE
2026-03-12 14:03:11  MapsSync ZHISTORYITEM        nav request → 400 Industrial Pkwy (intent)
2026-03-12 14:09:48  routined ZRTCLLOCATIONMO     fix 37.41,-122.01  speed 22.1 mph  h_acc 8 m
2026-03-12 14:18:02  routined ZRTCLLOCATIONMO     fix 37.39,-121.98  speed 54.6 mph  h_acc 6 m
2026-03-12 14:31:55  locationd WifiLocationHarvest saw BSSID a4:… near 37.39,-121.97 (corrob.)
2026-03-12 14:34:40  routined ZRTLEARNEDVISITMO   visit ENTRY 37.388,-121.972 (dwell begins)
2026-03-12 14:41:09  Photos EXIF GPS              IMG_0421 geotag 37.388,-121.972 (corrob.)
2026-03-12 15:20:13  knowledgeC /app/inFocus      "Slack" foreground (presence, no location)
2026-03-12 15:48:30  routined ZRTLEARNEDVISITMO   visit EXIT 37.388,-121.972 (dwell ends)
```

The power is in agreement *across independent producers*: routined says the device drove there at speed and dwelled; locationd independently saw a nearby AP; Photos independently geotagged a frame at the same coordinate. A claim that survives in only one store is a claim to flag, not to assert.

### Deletion, clearing, and anti-forensics

Users can erase location history through the UI, and you must know exactly what each control does and does not remove:

- **Settings → Privacy → Location Services → System Services → Significant Locations → Clear History** wipes the `ZRTLEARNEDVISITMO`/LOI rows from `Local.sqlite`/`Cloud-V2.sqlite`. But a `DELETE` in SQLite marks pages free, it does not zero them — deleted rows frequently survive in the **freelist and unallocated pages** of the `.sqlite` and, especially, in the **`-wal`**. Carve them.
- **Maps → clearing history** prunes `ZHISTORYITEM` similarly; the protobuf route BLOBs can linger in freed pages.
- **Toggling Location Services off** stops new `routined`/`locationd` writes but does not retroactively purge existing stores.
- **`Cache.sqlite` self-prunes** on its ~1-week rolling window regardless of user action — so its *absence* of old data is normal expiry, not necessarily anti-forensics; its *presence* of a gap inconsistent with heavy use is the signal.

```bash
# Recover deleted SQLite rows from freelist/unallocated + WAL
# (sqlite parsers that read the page structure, not just live rows)
python3 -m sqlite_carver --db Cache.sqlite --wal Cache.sqlite-wal -o carved/   # e.g. walitean / sqlparse / undark
# Or: 'undark -i Cache.sqlite' to dump every cell incl. freelist pages
```

> 🔬 **Forensics note:** A wiped Significant Locations list is itself evidence. If `Cache.sqlite` shows a dense, fast track through a neighborhood last Tuesday but `Local.sqlite` has *zero* learned visits and a `Z_PRIMARYKEY` `RTLearnedVisit` count of 0 with recent free pages, someone cleared history after the fact. Compare the `routined` story against the iCloud-synced `Cloud-V2` copy (the user may have cleared the phone but not the cloud, or vice-versa) and against the independent corroboration mesh below — deletion in one store rarely reaches all of them.

### Data-Protection class and lock state

The routined and locationd stores are protected files. In practice they fall under **Class C — `NSFileProtectionCompleteUntilFirstUserAuthentication`**: encrypted at rest, their keys loaded into memory at the first post-boot unlock and held until power-off. Consequences:

- **BFU (Before First Unlock):** keys are not in memory; these databases are unreadable even with a full file-system image. You get nothing useful from them.
- **AFU (After First Unlock):** keys are resident; a full file-system extraction decrypts them.
- **iOS 18+ inactivity reboot** (now ~72 h, down from the original week) silently forces an AFU device **back to BFU**, evaporating the keys. This is why the field rule is "acquire as close to seizure as possible, keep the device unlocked/charged, and never let it idle." See [[03-passcode-bfu-afu-and-inactivity]].

> ⚖️ **Authorization:** Location data is among the most legally sensitive artifacts you handle. In the United States, *Carpenter v. United States* (2018) established that historical location records carry a reasonable expectation of privacy — on-device Significant Locations and the `routined` track are squarely in that zone and generally require a warrant with location scope. Confirm your authority *names* location/historical-movement data before you extract it; "we had the phone" is not "we were authorized to reconstruct three months of the owner's movements." Document the acquisition class and lock state, because they bound what you could possibly have recovered.

## Hands-on

There is no shell on the device; every command runs **on the Mac** against an extracted image, a backup, or a Simulator container.

**Copy the store and its sidecars before any query (forensic discipline):**

```bash
# From a mounted full-file-system image (read-only mount)
SRC="/Volumes/FFS_IMAGE/private/var/mobile/Library/Caches/com.apple.routined"
DST="$HOME/case/routined"; mkdir -p "$DST"
cp "$SRC"/Cache.sqlite       "$DST"/ 2>/dev/null
cp "$SRC"/Cache.sqlite-wal   "$DST"/ 2>/dev/null
cp "$SRC"/Cache.sqlite-shm   "$DST"/ 2>/dev/null
shasum -a 256 "$DST"/Cache.sqlite*       # record hashes in your notes
```

**Inspect the schema before trusting any column name:**

```bash
sqlite3 "$DST/Cache.sqlite" ".schema ZRTCLLOCATIONMO"
sqlite3 "$DST/Cache.sqlite" "SELECT MIN(datetime(ZTIMESTAMP+978307200,'unixepoch')),
                                    MAX(datetime(ZTIMESTAMP+978307200,'unixepoch')),
                                    COUNT(*) FROM ZRTCLLOCATIONMO;"
# → establishes the real retention window and point count for THIS image
```

**Pull a speed-aware track to CSV (drops invalid speeds):**

```bash
sqlite3 -header -csv "$DST/Cache.sqlite" "
  SELECT datetime(ZTIMESTAMP+978307200,'unixepoch') AS fix_utc,
         ZLATITUDE AS lat, ZLONGITUDE AS lon,
         round(ZSPEED*2.23694,1) AS mph, ZCOURSE AS heading,
         ZHORIZONTALACCURACY AS h_acc
  FROM ZRTCLLOCATIONMO
  WHERE ZSPEED >= 0
  ORDER BY ZTIMESTAMP;" > "$HOME/case/routined_track.csv"
```

**Query the `locationd` Wi-Fi/cell cache (FFS only — root-owned):**

```bash
# Wi-Fi APs the device personally observed, with coordinates and time
sqlite3 -header -column cache_encryptedB.db ".tables"      # confirm table names first
sqlite3 -header -csv cache_encryptedB.db "
  SELECT datetime(Timestamp + 978307200,'unixepoch') AS seen_utc,
         MAC, Latitude, Longitude, HorizontalAccuracy
  FROM WifiLocationHarvest                                  -- 'own observation' table
  ORDER BY Timestamp DESC;" > ~/case/wifi_harvest.csv
# Note: harvest tables = this device saw it; non-harvest = Apple-supplied cache. Verify columns.
```

**Let the community tooling do the version-aware heavy lifting:**

```bash
# iLEAPP — point at the extraction root; it auto-detects routined/locationd/Maps
python3 ileapp.py -t fs -i /path/to/ffs_root -o ~/case/ileapp_out
#   reports: "Routined Cache Locations", "Significant Locations",
#            "Apple Maps Search/Navigation History", "Locationd ..." etc.

# APOLLO — Pattern-of-Life timeline across knowledgeC + routined + biome
python3 apollo.py -o sql -p ios -d ~/case/extraction   # emits one unified timeline
```

**Decode a Maps route protobuf (start/destination) from `MapsSync_0.0.1`:**

```bash
sqlite3 "$HOME/case/MapsSync_0.0.1" \
  "SELECT Z_PK, length(ZROUTEREQUESTSTORAGE) FROM ZHISTORYITEM
   WHERE ZROUTEREQUESTSTORAGE NOT NULL;"
# Export one BLOB and inspect the protobuf structure:
sqlite3 "$HOME/case/MapsSync_0.0.1" \
  "SELECT writefile('/tmp/route.pb', ZROUTEREQUESTSTORAGE) FROM ZHISTORYITEM WHERE Z_PK=42;"
protoc --decode_raw < /tmp/route.pb     # or: protobuf-inspector < /tmp/route.pb
```

**Pull Maps history from a backup (routined is *not* there — Maps is):**

```bash
# MapsSync_0.0.1 IS captured in an iTunes/Finder backup (it's in an App Group container);
# the routined/locationd stores are NOT. Map the backup's mangled filenames to real paths:
pymobiledevice3 backup2 list <backup_dir> | grep -i 'Maps/MapsSync'
# Backups hash the domain+path into Manifest.db; let a tool de-mangle, or query Manifest.db:
sqlite3 <backup_dir>/Manifest.db \
  "SELECT fileID, relativePath FROM Files WHERE relativePath LIKE '%MapsSync_0.0.1';"
# fileID is the on-disk name under the two-char sharded backup tree.
```

**Convert a CSV track to GPX for mapping (quick awk):**

```bash
# expects the routined_track.csv from above (utc,lat,lon,mph,heading,h_acc)
# NB: uses POSIX gsub (not gawk's gensub) so it runs on macOS's stock BSD awk.
{ echo '<?xml version="1.0"?><gpx version="1.1"><trk><trkseg>';
  tail -n +2 ~/case/routined_track.csv | awk -F, \
    '{t=$1; gsub(/ /,"T",t); printf "<trkpt lat=\"%s\" lon=\"%s\"><time>%sZ</time></trkpt>\n",$2,$3,t}';
  echo '</trkseg></trk></gpx>'; } > ~/case/track.gpx
# open track.gpx in any GIS / Google Earth / gpx.studio
```

## 🧪 Labs

> The device-only daemons that produce these stores — **`routined` and `locationd` do not run on the iOS Simulator**, and `xcrun simctl location` injects a *live* `CLLocation` to running apps **without** writing `Cache.sqlite`/`Local.sqlite`. So the parsing labs use a **public sample forensic image**, and the Simulator lab exists specifically to *prove* that fidelity gap rather than to generate routined data.

### Lab 1 — Build a speed-aware track (substrate: public sample image)

Use a full-file-system iOS reference image (Josh Hickman's iOS images on thebinaryhick.blog / Digital Corpora, or the iLEAPP test data). *Fidelity caveat: a real device image — the Simulator cannot produce `ZRTCLLOCATIONMO`.*

1. Locate `com.apple.routined/Cache.sqlite` in the image; copy it **with `-wal`/`-shm`**; hash all three.
2. Run the `MIN/MAX/COUNT` schema query — what is the **real** retention window and point count for this image? Does it match the "~1 week" expectation?
3. Export the speed-aware CSV, then the GPX. Map it. Identify the single fastest fix: what's the `mph`, the `h_acc_m`, and is the accuracy good enough to trust the speed?
4. Find a cluster of low/zero-speed fixes lasting >30 min — that's a dwell. Note the coordinate; you'll cross-check it in Lab 2.

### Lab 2 — Significant Locations & the backup blind spot (substrate: public sample image)

1. From the same image, copy `Local.sqlite` (and `Cloud-V2.sqlite` if present) with sidecars.
2. `.schema ZRTLEARNEDVISITMO` — confirm the entry/exit/creation column names for *this* OS version before querying (they drift).
3. Run the visits query. Does the longest-dwell visit coincide with the Lab 1 dwell cluster? Join to `ZRTLEARNEDLOCATIONOFINTERESTMO`/`ZRTMAPITEMMO` to put a name on "home."
4. **The blind-spot test:** if the image set also ships an *iTunes/Finder backup* of the same device, search that backup tree for `Cache.sqlite`/`Local.sqlite`. Confirm Significant Locations are **absent** from the backup — proving why acquisition class is part of the finding.

### Lab 3 — Maps intent: decode a route protobuf (substrate: public sample image / read-only walkthrough)

1. Find `MapsSync_0.0.1` under `…/AppGroup/<GUID>/Library/Maps/`.
2. List `ZHISTORYITEM` rows with non-null `ZROUTEREQUESTSTORAGE`. How many history items survive (test the "~15 max" claim)?
3. `writefile` one BLOB and run `protoc --decode_raw`. Identify the start and destination coordinate fields in the raw protobuf output.
4. Write the one-line finding: "At <time> the user requested navigation from <A> to <B>." Note that this is *intent*, distinct from the `routined` *presence* track of Lab 1.

### Lab 4 — Prove the Simulator fidelity gap (substrate: Simulator)

This lab demonstrates why no location lab can use the Simulator as a routined stand-in.

```bash
xcrun simctl list devices | grep Booted        # or boot one
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl location "$DEV" set 37.3349,-122.0090      # inject a fix
```

1. Open Maps in the booted Simulator — confirm the blue dot jumps to the injected coordinate (apps *do* receive it).
2. Now hunt the on-disk container for a routined store:
   ```bash
   find ~/Library/Developer/CoreSimulator/Devices/$DEV/data \
        -iname 'Cache.sqlite' -path '*routined*' 2>/dev/null
   ```
   It returns nothing. **The injected location never lands in any `routined`/`locationd` store** — there is no such daemon on the Simulator.
3. Write the one-sentence methodology note you'd put in a report: *why* Simulator location is useless as a forensic source, and which substrate you must use instead.

### Lab 5 — Fuse a unified movement timeline (substrate: public sample image)

1. From Lab 1's `Cache.sqlite`, Lab 2's `Local.sqlite`, the image's `Photos.sqlite` (EXIF GPS — see [[06-photos-and-the-camera-roll]]), and `knowledgeC.db` (see [[01-knowledgec-db-deep-dive]]), export each as timestamped CSV in **UTC**.
2. Run iLEAPP and APOLLO over the whole extraction; compare their auto-built timelines against your hand-built CSVs — do they agree on the dwell and the fastest fix?
3. Merge into one table sorted by UTC. For one 3-hour window, write a narrative: searched (Maps) → moved at speed (routined fixes) → arrived/dwelled (visit) → took a geotagged photo (Photos EXIF) → app activity (knowledgeC). Flag any single-source claim that lacks corroboration.

### Lab 6 — Recover cleared location rows (substrate: public sample image)

If your sample set includes an image where Significant Locations or Maps history was cleared (or clear it yourself in a Simulator's copy of a populated SQLite, then carve), practice recovery:

1. Establish the baseline: `SELECT Z_NAME, (live count) FROM Z_PRIMARYKEY` for `RTLearnedVisit`. Note any mismatch between the entity's stored max `Z_PK` and the live row count — missing PKs imply deletions.
2. Run a freelist/WAL carver (`undark`, `walitean`, or a page-walking parser) over `Local.sqlite` + its `-wal`. Dump every cell, including freed pages.
3. Diff carved rows against live rows. Did you recover visits the live query does not return? Map them; note that recovered = "was present, then deleted," a distinct and reportable finding.
4. Cross-check: do the recovered (deleted) visits correlate with surviving `Cache.sqlite` fixes or `Cloud-V2.sqlite` rows the user forgot to clear? That cross-store survival is what makes a "I cleared my history" defense fail.

## Pitfalls & gotchas

- **Epoch confusion.** `routined` and Maps Core Data stores use **Mac Absolute Time** (add `978307200`). Photo EXIF uses calendar strings; Unix-epoch columns appear elsewhere; some Apple stores use nanoseconds. Mixing epochs throws timestamps off by ~31 years — see [[00-the-ios-timestamp-zoo]]. Always sanity-check that converted dates fall in the case window.
- **Timezone.** Store the truth in **UTC** in your timeline; only render local time for the report, and state which timezone. `routined` rows are UTC; do not double-apply an offset.
- **WAL not checkpointed.** The freshest fixes hide in `Cache.sqlite-wal`. Forget the sidecars and you'll under-report recent movement and possibly miss the decisive point. Copy the trio; never open the original live.
- **`ZSPEED`/`ZCOURSE` sentinels.** `−1.0` means "unavailable," not "stopped" / "due north." Filter `>= 0` or you'll report phantom 0-mph stops and false headings.
- **Horizontal accuracy is not optional.** A coordinate with `ZHORIZONTALACCURACY` of 1500 m is a Wi-Fi/cell estimate; placing it on a specific address is malpractice. Always carry accuracy alongside the point.
- **Acquisition-class blind spots.** Significant Locations and the `locationd` root caches are **not** in iTunes/iCloud backups; they require a full file-system extraction. "Not found" in a logical acquisition is not "did not exist." Conversely, **ADP / E2E iCloud** breaks the cloud path for the synced `Cloud-V2` data — see [[06-icloud-acquisition-and-advanced-data-protection]].
- **Lock state evaporates keys.** A device that idles past the iOS 18+ ~72 h inactivity-reboot window drops from AFU to BFU and the routined/locationd stores become unreadable. Acquire fast; keep it awake.
- **Schema drift is real.** Column and even table names in `Local.sqlite`/`Cloud-V2.sqlite` and `MapsSync` have changed across iOS 11/12/13/17/18. Dump the live `.schema` first; lean on iLEAPP/APOLLO's version-aware modules but read their query files.
- **Two `cache_encryptedB.db` files.** One under `com.apple.routined/`, one under `locationd/`. Different directories, different contents. Cite the full path in every note.
- **Don't over-read `locationd` caches.** `cache_encryptedB.db` (locationd) caches *observed* Wi-Fi/cell infrastructure, not a clean record of the owner's path. It corroborates "in range of tower/AP X," not "stood at coordinate Y."
- **Harvest vs. download tables.** In the `locationd` caches, only the `*Harvest` tables are the *device's own* observations; the non-harvest tables are Apple's supplied cache. Quoting a non-harvest row as "the phone was here" overstates the evidence — it only means "Apple told the phone this AP/tower lives here."
- **`ZSPEED` is device speed, not vehicle speed.** A phone tossed on a passenger seat reads the car's speed; a phone in a runner's hand reads running speed. It is the *device's* kinematics — usually a fair proxy, but say so.
- **Cleared ≠ gone.** A `DELETE` leaves rows in the freelist/`-wal`. "Significant Locations was empty" is not "the user never had any" — carve before you conclude a negative.
- **Two epochs even within Maps.** `MapsSync` mixes Core Data Mac-Absolute-Time columns with protobuf-internal timestamps inside the route BLOBs; decode each in its own frame.

## Key takeaways

- `com.apple.routined`'s **`Cache.sqlite` → `ZRTCLLOCATIONMO`** records each fix with **GNSS-derived speed and heading** — an independent velocity measurement that has made and broken alibis. Short retention (~1 week); acquire fast.
- **Significant Locations** (learned home/work) live in **`Local.sqlite` / `Cloud-V2.sqlite`** as visits + LOIs and are **excluded from backups** — they demand a full file-system (or credentialed cloud) acquisition, so the acquisition method is part of the finding.
- **`locationd`** keeps lower-level **Wi-Fi/cell geo caches** under `/private/var/root/Library/Caches/locationd/` (`cache_encrypted*.db`) — root-owned, FFS-only, readable as plain SQLite once decrypted.
- **Apple Maps** (`MapsSync_0.0.1`, `ZHISTORYITEM.ZROUTEREQUESTSTORAGE` protobuf) records *intent* — searches and route endpoints — distinct from `routined`'s *presence*; the parked-car drop pins an on-foot coordinate at a known minute.
- Everything is **Core Data in Mac Absolute Time** (`+978307200`), Data-Protection **Class C** — encrypted in BFU, readable in AFU, and re-locked by the iOS 18+ **~72 h inactivity reboot**.
- **Fuse, don't trust one store:** routined track + visits + photo EXIF + knowledgeC/Biome + Wi-Fi joins, all normalized to UTC, with horizontal accuracy carried on every point.
- The **iPhone is the location witness** a Mac never is: always-on GNSS + cellular + motion coprocessor produce the rich Significant-Locations + speed corpus the macOS course's thin location caches lack.

## Terms introduced

| Term | Definition |
|---|---|
| `routined` | iOS pattern-of-life daemon (CoreDuet/CoreRoutine family) that samples `locationd`, stores raw fixes, and learns Significant Locations. |
| `locationd` | Low-level CoreLocation provider daemon; computes `CLLocation` and caches Wi-Fi/cell → coordinate mappings. |
| `Cache.sqlite` | `routined` store of raw location fixes (`ZRTCLLOCATIONMO`); short retention (~1 week). |
| `ZRTCLLOCATIONMO` | Core Data table of serialized `CLLocation`s: lat/lon, altitude, **speed (m/s)**, course, horizontal/vertical accuracy, timestamp. |
| `ZSPEED` | Instantaneous device speed in m/s, GNSS-Doppler-derived; `−1.0` = unavailable. |
| Significant Locations | Learned recurring places (home/work) the user can view in Settings; stored as LOIs in `Local.sqlite`/`Cloud-V2.sqlite`. |
| `ZRTLEARNEDVISITMO` | `routined` table of dwell *visits* (entry/exit/creation/expiration + coordinate + confidence). |
| `ZRTLEARNEDLOCATIONOFINTERESTMO` | `routined` table of learned Locations of Interest (LOIs) backing the Significant Locations list. |
| `ZRTMAPITEMMO` | `routined` table of reverse-geocoded named places (address/POI) linked to visits and LOIs. |
| `Cloud-V2.sqlite` | iCloud-synced Significant Locations store (renamed from `Cloud.sqlite` at iOS 13); excluded from standard backups. |
| `cache_encryptedB.db` | `locationd` cache of observed Wi-Fi APs / cell towers and their estimated coordinates (descendant of `consolidated.db`). |
| `MapsSync_0.0.1` | Current Apple Maps history Core Data store (`ZHISTORYITEM`); route endpoints in the `ZROUTEREQUESTSTORAGE` protobuf BLOB. |
| Parked-car artifact | `routined` record of the location/time the device disconnected from car Bluetooth/CarPlay while moving. |
| Mac Absolute Time | Apple timestamp epoch of 2001-01-01 UTC; add `978307200` to convert to Unix. |
| Inactivity reboot | iOS 18+ feature (~72 h) that returns an idle AFU device to BFU, evaporating Data-Protection keys. |
| Harvest table | In the `locationd` caches, a table of the *device's own* Wi-Fi/cell observations (vs. the non-harvest Apple-supplied cache). |
| `consolidated.db` | Pre-iOS-5 location cache whose disclosure triggered the 2011 "iPhone tracking" controversy; ancestor of `cache_encrypted*.db`. |
| `Z_PRIMARYKEY` | Core Data housekeeping table mapping entity names to `Z_ENT` ids and row counts; the entity catalog of any Core Data store. |
| LOI | Location of Interest — `routined`'s internal term for a learned recurring place backing the Significant Locations list. |

## Further reading

- Sarah Edwards (mac4n6.com) — "On the Tenth Day of APOLLO… An Oddly Detailed Map of My Recent Travels" and the protobuf-in-iOS series; **APOLLO** (`github.com/mac4n6/APOLLO`) `routined_*` and `locationd_*` modules (read the `.txt` query files).
- Alexis Brignoni — **iLEAPP** (`github.com/abrignoni/iLEAPP`) routined / Significant Locations / Apple Maps / locationd parsers.
- The Forensic Scooter — "iPhone Device Speeds via `Cache.sqlite` > `ZRTCLLOCATIONMO`" and "iOS Location Services and System Services ON or OFF?"
- MSAB — "SQLite Secrets: iOS Location Data"; Mattia Epifani / ZENA Forensics (blog.digital-forensics.it) — "A first look at iOS 18 forensics" (location-artifact acquisition-class table).
- Cellebrite — *"Was it actually there?"* iOS location booklet (2025 ed.); Elcomsoft — "Significant Locations, iOS 14 and iCloud" and "Apple Probably Knows What You Did Last Summer."
- Hexordia / Magnet Forensics — iOS 18 inactivity-reboot analyses (BFU/AFU impact on location acquisition).
- Mary Mara / Heather Mahalik (SANS FOR585) — iOS location-artifact methodology; RealityNet `iOS-Forensics-References` (curated path index).
- Apple Support — "Find your parked car in Maps"; "About Location Services & Privacy"; *Carpenter v. United States*, 585 U.S. ___ (2018).

---
*Related lessons: [[01-knowledgec-db-deep-dive]] | [[02-biome-and-segb-streams]] | [[06-photos-and-the-camera-roll]] | [[00-the-ios-timestamp-zoo]] | [[01-building-a-unified-timeline]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[05-full-file-system-acquisition]] | [[06-icloud-acquisition-and-advanced-data-protection]]*
