---
title: "Deleted-data recovery"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 14
est_time: "50 min read + 25 min labs"
prerequisites: [communications-imessage-and-sms, photos-and-the-camera-roll]
tags: [ios, forensics, deleted-data, sqlite, wal, carving, recovery, dfir]
last_reviewed: 2026-06-26
---

# Deleted-data recovery

> **In one sentence:** On iOS, "deleted" is a question, not a conclusion — the bulk of user data lives in SQLite databases where a deletion is most often a flipped flag, a row parked in the write-ahead log, or a cell unlinked-but-not-overwritten, and only effaceable-storage / crypto-erase makes something genuinely, mathematically gone.

## Why this matters

Almost every pattern-of-life artifact you have studied in this module — iMessage (`sms.db`), the photo catalog (`Photos.sqlite`), Notes (`NoteStore.sqlite`), Safari history, call history, health — is a SQLite database. SQLite is a *journaling, copy-tolerant, lazily-compacting* file format: it would rather mark space reusable than scrub it, would rather defer a write to a sidecar log than touch the main file, and would rather keep an app-level "trash" flag than physically remove a row. Each of those design choices is a recovery opportunity. The same techniques you already know from macOS — copy the WAL, parse the freelist, read soft-delete flags, carve unallocated pages — port verbatim to the iOS artifact databases. What changes on iOS is the *acquisition floor underneath* the SQLite layer: whether you even have the decrypted file depends on lock state and Data-Protection class, and whether the deleted *content* still exists underneath depends on APFS block reuse, flash TRIM, and crypto-erase. This lesson teaches you to treat a database as a crime scene: never trust the `SELECT`, always interrogate the file.

## Concepts

### The four planes where deleted data survives

A single `.sqlite` file is not one container — it is several overlapping ones, and a deletion lands in a different plane depending on *how* the app deleted it:

```
┌─────────────────────────────────────────────────────────────────────┐
│  PLANE 1 — APPLICATION SOFT-DELETE  (a flag, not a deletion at all)   │
│    ZTRASHEDSTATE=1 / ZMARKEDFORDELETION=1 / chat_recoverable_*        │
│    → row is LIVE and fully queryable; you recover it by READING       │
├─────────────────────────────────────────────────────────────────────┤
│  PLANE 2 — WRITE-AHEAD LOG  (-wal / -shm sidecars; pre-checkpoint)    │
│    recent INSERTs *and* DELETEs that have not yet checkpointed        │
│    → the WAL frequently holds rows the main table no longer shows     │
├─────────────────────────────────────────────────────────────────────┤
│  PLANE 3 — FREELIST + IN-PAGE FREEBLOCKS  (truly DELETEd rows)        │
│    cells unlinked from the b-tree but bytes not overwritten           │
│    → recover by CARVING the unallocated regions of pages              │
├─────────────────────────────────────────────────────────────────────┤
│  PLANE 4 — UNALLOCATED FILESYSTEM  (the whole .sqlite file is gone)   │
│    the file was deleted; APFS extents not yet reused/TRIMmed          │
│    → recover by carving the FFS image for SQLite headers              │
└─────────────────────────────────────────────────────────────────────┘
              ▼ below all four planes ▼
   CRYPTO-ERASE / EFFACEABLE STORAGE — class key destroyed → GENUINELY GONE
```

The discipline is to work top-down: read the soft-delete flags first (cheapest, highest-fidelity), grab and parse the WAL second (volatile, collapses on checkpoint), carve the freelist third, carve the FFS image last. Skipping Plane 1 because you reached for a carver is the classic rookie error — you carve garbage out of unallocated when the row was sitting *live* in the table behind a flag the whole time.

> 🖥️ **macOS contrast:** This is the *identical* technique you ran against `chat.db`, `History.db`, and `knowledgeC.db` on the Mac — same file format, same WAL, same freelist, same epoch math. The only differences are the path (`/private/var/mobile/...` instead of `~/Library/...`) and the acquisition floor (FileVault/SEP on the Mac becomes Data-Protection class keys on iOS; see [[bfu-vs-afu-and-data-protection-classes]]). If you can carve a Mac SQLite store, you can carve an iOS one — the schemas just have `Z`-prefixed Core Data column names.

### The SQLite file header — read it before you query

The first 100 bytes of every SQLite database are a fixed header. Three offsets matter for recovery; read them with `hexdump`/`xxd` before you ever open the file in a tool:

| Offset | Bytes | Field | Why you care |
|---|---|---|---|
| 0 | 16 | Magic `"SQLite format 3\0"` | Confirms it's a DB (and what a carver hunts for in Plane 4) |
| 16 | 2 | Page size (big-endian) | The carve unit — every page is this many bytes |
| 18 | 1 | File-format **write** version | `1` = rollback journal, `2` = **WAL mode** |
| 19 | 1 | File-format **read** version | matches write version in practice |
| 32 | 4 | Page number of first **freelist trunk** page | entry point to Plane 3 |
| 36 | 4 | Total **freelist page count** | how much deleted-page space exists |

If offset 18 reads `0x02`, the database is in WAL mode and **a `-wal` sidecar may hold data the main file does not** — that single byte tells you whether grabbing the sidecars is mandatory (it nearly always is on iOS; Apple ships WAL mode for almost everything). If offsets 32/36 are non-zero, there are freelist pages full of deleted records waiting to be carved.

### A `SELECT` is a write — the copy-before-query rule

Before any plane discussion, the discipline that makes recovery defensible: **opening a SQLite database is a mutating act.** A read-only intent does not produce a read-only effect. Connecting to a WAL-mode database can create or extend the `-shm`, can append a fresh `-wal`, and — if the connection closes cleanly or hits the auto-checkpoint threshold — can **checkpoint the WAL into the main file**, permanently collapsing the very recoverable frames (Plane 2) you came to harvest. Even a pure `SELECT` takes a lock and can trigger this. Worse, some GUI viewers and parsers run a `VACUUM` or rewrite indexes on open, wiping Plane 3.

The non-negotiable workflow, in order:

1. **Image first.** Acquire at the filesystem level so you have the original byte-for-byte ([[acquisition-sop-and-chain-of-custody]]).
2. **Copy the database as a set** onto a working volume — `.sqlite` + `-wal` + `-shm` (+ `-journal`). Hash each file.
3. **Query the copy only.** Never the original, never a sidecar-less copy.
4. **Parse WAL and freelist before any tool that might checkpoint or vacuum.**

This is the iOS analogue of the macOS rule you already practiced — and the reason every command in this lesson copies before it queries.

### Plane 2 — the WAL/SHM/journal sidecars (grab them or lose evidence)

Since SQLite 3.7.0 the default-on-iOS durability mode is **write-ahead logging**. Instead of modifying the main `.sqlite` file in place, SQLite appends *new page images* to a `<db>-wal` file and keeps a `<db>-shm` shared-memory index that tells readers which version of each page is current. The main file is only updated during a **checkpoint** (automatic at ~1000 dirty WAL pages by default, or on clean close).

The forensic consequence is enormous: **between checkpoints, the newest truth lives in the `-wal`, not the table.**

```
  app.sqlite              app.sqlite-wal                 app.sqlite-shm
 ┌──────────┐            ┌────────────────────────┐     ┌──────────────┐
 │ page 1   │            │ WAL header (32 bytes)  │     │ wal-index    │
 │ page 2   │  ◄──────   │ frame: page 5  (v2)    │     │ (which frame │
 │ page 3   │  reads     │ frame: page 5  (v3)    │     │  is current  │
 │ page 4   │  resolve   │ frame: page 9 (COMMIT) │     │  per page)   │
 │ page 5   │  through   │ frame: page 2  (v2)    │     └──────────────┘
 │ ...      │  the WAL   │ ...                    │
 └──────────┘            └────────────────────────┘
   stale copies            newest copies + commit markers
```

WAL file layout you will hexdump:

- **32-byte WAL header.** Magic `0x377F0682` (page checksums computed big-endian) or `0x377F0683` (native/little-endian); then format version (`3007000`), database page size, checkpoint sequence number, two 32-bit **salt** values, two 32-bit checksums.
- **Frames**, each = a **24-byte frame header** + one full page image. The frame header is: page number (4) · *database size in pages after commit* (4 — **non-zero only on a commit frame**) · salt-1 (4) · salt-2 (4) · checksum-1 (4) · checksum-2 (4). The salts in a valid frame must match the WAL header's salts; a salt mismatch marks a **stale frame** left over from a previous WAL generation — and stale frames are pure gold, because they hold *committed-then-superseded* page images that no live reader will ever return.

Why the WAL holds deletes as well as inserts: a `DELETE` rewrites the affected b-tree page (the cell is unlinked) and that *post-delete* page image is written as a WAL frame — but so was the *pre-delete* page image from whenever that page last changed. Walk every frame for a given page number and you see the page's history. A message the user deleted five minutes ago, that the app has since hidden, is commonly still sitting in a pre-delete WAL frame because no checkpoint has fired.

#### Frame-walking: reconstructing a page's history

The recovery move with the WAL is not "convert it to a DB" — it is **walk every frame, grouped by page number, in order**. For a single hot page (say the table-leaf page holding recent `sms.db` rows) you will often see a sequence like:

```
 frame  page#  commit?   what changed
 ─────  ─────  ───────   ──────────────────────────────────────────────
   12     47      no      page 47 v1 — rows A,B,C present
   18     47      no      page 47 v2 — rows A,B,C,D (D inserted)
   23     47    COMMIT    page 47 v3 — rows A,B,C  (D... no: B DELETEd)
   ...
 (stale) 47      no      page 47 vN — left from a previous WAL generation
```

Diffing v1→v2→v3 of the *same page number* tells you exactly which cells appeared and vanished and *when* (commit frames anchor the timeline). The just-deleted row's bytes are still present in the earlier frame's page image even though the latest frame (and the main file after checkpoint) no longer references them. **Stale frames** (salt mismatch) extend this history backward into a previous WAL lifetime — `walitean` and SQLite Dissect surface them; a manual `xxd` of the frame region finds them when tools choke on a malformed WAL.

#### Rollback-journal mode (the rarer sidecar)

Not every iOS DB is WAL. A database in the older **rollback-journal** mode (header offset 18 == `0x01`) writes a `<db>-journal` sidecar holding the *original* page images so a failed transaction can be rolled back. Forensically that is the mirror image of the WAL: the journal contains **pre-change** pages — i.e. the rows *as they were before* the last (possibly deleting) transaction. A hot-journal left after a crash is a snapshot of the database one transaction in the past. Grab `-journal` with the same discipline you grab `-wal`; it is rarer on modern iOS but appears in third-party apps that override the default.

> 🔬 **Forensics note:** **Copy the sidecars with every database — always.** `cp sms.db /evidence/` alone is malpractice: you have left the `-wal` (newest rows, including just-deleted ones) and `-shm` (the index that resolves them) behind, and worse, opening the lone `.sqlite` in a tool can trigger a **checkpoint or a fresh WAL**, silently destroying the very evidence you came for. The rule is `cp sms.db sms.db-wal sms.db-shm /evidence/` (and `sms.db-journal` if a rollback-mode DB is present), preserve them as a *set*, work on the set, and only then query. A `tar`/`ditto` of the whole app container is the safe move on iOS — see [[app-sandbox-and-filesystem-layout]].

> 🔬 **Forensics note:** Forcing a checkpoint to "merge the WAL in" before analysis is a destructive anti-pattern. Checkpointing collapses superseded frames — you keep the *current* state and lose the *history*. Parse the WAL **independently** (walitean, the DC3 SQLite Dissect carver, or Sanderson's Forensic Browser for SQLite, which presents WAL frames as recoverable rows) so you see every version of every page, then reconcile against the main table.

### Plane 3 — the freelist and in-page freeblocks (true DELETEs)

When a row is genuinely deleted (no soft-delete flag, and after any WAL checkpoint), SQLite does **not** zero the bytes. It does one of two things:

1. **Frees the cell within its page.** The cell pointer is removed from the page's cell-pointer array and the freed span is added to that page's **freeblock chain**. A b-tree page header is 8 bytes (12 on interior pages): byte 0 = page type (`0x0D` leaf-table, `0x05` interior-table, `0x0A` leaf-index, `0x02` interior-index), bytes 1–2 = **offset to the first freeblock** (0 if none), bytes 3–4 = cell count, bytes 5–6 = start of the cell-content area, byte 7 = fragmented free bytes. Each freeblock is `[2-byte next-freeblock offset][2-byte size]` followed by **the original record bytes, untouched**. The record's payload — its serial-type header and column values — is still physically there.

2. **Frees the whole page** (if a page empties out). The page is added to the **freelist**: a chain of freelist *trunk* pages (each listing leaf-page numbers) reachable from offset 32 of the file header. A freed page keeps its old cell content; only the first few bytes are repurposed as freelist bookkeeping. An entire deleted b-tree leaf full of records can sit on the freelist intact.

A b-tree leaf page is the carving battlefield. Its anatomy:

```
 byte 0 ┌──────────────────────────────────────────────┐
        │ page header (8 bytes): type · freeblock-ptr · │
        │   cellcount · cell-content-start · frag        │
        ├──────────────────────────────────────────────┤
        │ cell-pointer array (2 bytes per LIVE cell) ──► │ grows down
        ├──────────────────────────────────────────────┤
        │            UNALLOCATED  (slack)                │ ◄── carve here
        │      + FREEBLOCK chain woven through the        │     (deleted cells
        │        cell-content area below                  │      live in both)
        ├──────────────────────────────────────────────┤
        │ cell content area (live records) ◄──────────── │ grows up
 end    └──────────────────────────────────────────────┘
```

A deletion removes the cell's 2-byte pointer from the array and turns its old span into a freeblock — but the record bytes stay in the cell-content area. So deleted records hide in three regions: the **freeblock chain**, **whole free pages** on the freelist, and the **unallocated slack** between the (now-shorter) pointer array and the cell-content start.

Carving exploits the fact that a SQLite **record** is self-describing. Its layout is: a varint **payload length**, a varint **rowid**, then a **record header** = a varint header-length followed by one **serial type** varint per column (0 = NULL, 1 = 1-byte int, … 7 = float, 8/9 = literal 0/1, ≥12 even = BLOB of `(N-12)/2` bytes, ≥13 odd = TEXT of `(N-13)/2` bytes), then the column bodies concatenated. A worked example — a `(id INTEGER PRIMARY KEY, body TEXT)` row holding `(35, "hi")`, where the `INTEGER PRIMARY KEY` is encoded as `NULL` in the record because its value already lives in the rowid:

```
  05 23 03 00 11 68 69
  │  │  │  │  │  └──┴── body: "hi"  (0x68 0x69)
  │  │  │  │  └──────── serial type 0x11 = 17 → TEXT, len (17-13)/2 = 2 bytes
  │  │  │  └─────────── serial type 0x00 = NULL — the INTEGER PK, value lives in the rowid
  │  │  └────────────── record-header length = 3 (this varint + the 2 serial-type bytes)
  │  └───────────────── rowid = 0x23 = 35
  └──────────────────── payload length = 5 (3-byte header + 2-byte body)
```

A carver scans the unallocated regions for byte runs that *validate* as such a header (header-length plausible, serial types in range, body lengths summing correctly) consistent with the live schema, then decodes the body. That is exactly what **undark**, **bring2lite**, **FQLite**, **DC3 SQLite Dissect**, and Mari DeGrazia's **sqlparse** do — and why constraining `--cellcount-min`/`--rowsize-min` to the known schema width sharply cuts false positives.

> 🖥️ **macOS contrast:** Same freelist, same freeblock chain, same record encoding you parsed on macOS — SQLite's on-disk format is platform-independent. A serial-type carve you wrote for `~/Library/Mail` Envelope Index works unmodified on iOS `sms.db`. The format is the constant; only the schema column names (`ZTEXT`, `ZHANDLE`, the `Z`-prefix Core Data convention) differ.

### Plane 1 — the soft-deletes that aren't deletions at all

This is the highest-value, lowest-effort plane, and the one investigators most often miss because the UI says "Deleted." Three flagship iOS examples — the row is **live and fully queryable**; you "recover" it by reading a column:

**Photos — `Photos.sqlite`, `ZASSET` table.** "Delete" sends an asset to *Recently Deleted* (a 30-day trash). The asset row stays put; the originals stay in `DCIM`/`PhotoData`. The signal:

| Column | Meaning |
|---|---|
| `ZASSET.ZTRASHEDSTATE` | `1` = in Recently Deleted; `0` = live in the library |
| `ZASSET.ZTRASHEDDATE` | Mac Absolute Time the asset was trashed (`+978307200` → Unix) |
| `ZASSET.ZTRASHEDBYPARTICIPANT` | who trashed it (shared-library context) |

> The table was named **`ZGENERICASSET`** before iOS 14 and **`ZASSET`** from iOS 14 onward — confirm which against the actual schema (`.schema` / `SELECT name FROM sqlite_master`) rather than assuming; sample-image lessons span both eras.

**Notes — `NoteStore.sqlite`, `ZICCLOUDSYNCINGOBJECT` table.** A deleted note is flagged `ZMARKEDFORDELETION = 1` and lingers until a sync purge (or, notably, until the user backgrounds the Notes app — capture live if you can). The note title/body live in `ZICNOTEDATA.ZDATA` as a **gzip-compressed protobuf** (the `apple_cloud_notes_parser` / `sqlite_miner` decompress-and-decode this; raw `strings` on the DB even surfaces fragments of decompressed text).

**Messages — `sms.db`, the "Recently Deleted" tables (iOS 16+).** Before iOS 16 a deleted iMessage row was simply `DELETE`d, leaving only a *gap in the `ROWID` sequence* as proof it ever existed (negative evidence — see [[communications-imessage-and-sms]]). From **iOS 16**, deletion is a 30-day soft-delete: the `message` row persists, but its link moves out of `chat_message_join` into **`chat_recoverable_message_join`**, with parts tracked in **`recoverable_message_part`**. A message in *Recently Deleted* is therefore fully recoverable by joining through the recoverable tables instead of the normal join — no carving required.

The "Recently Deleted" / trash pattern recurs across the platform — Apple added a 30-day trash to store after store, and each is a Plane-1 read once you know the flag or table. A working map (verify column names against the actual schema, which drifts by iOS version):

| Store | Database | Soft-delete mechanism |
|---|---|---|
| Photos | `Photos.sqlite` | `ZASSET.ZTRASHEDSTATE = 1` (+ `ZTRASHEDDATE`); originals remain in `PhotoData`/`DCIM` |
| Notes | `NoteStore.sqlite` | `ZICCLOUDSYNCINGOBJECT.ZMARKEDFORDELETION = 1` until sync purge / app background |
| Messages | `sms.db` | iOS 16+: `chat_recoverable_message_join` + `recoverable_message_part` (30-day) |
| Voicemail | `voicemail.db` | `voicemail.trashed_date` set (non-zero) → deleted voicemails retained for ~30 days |
| Safari | `History.db` | `history_tombstones` table records deleted history entries (sync-deletion stubs) |
| Mail | `Envelope Index` / Protected Index | deleted messages move to a Trash mailbox before purge; `.emlx` files linger |
| Calendar | `Calendar.sqlite` | events flagged removed before sync compaction |
| Reminders | `Reminders`/`Store.sqlite` (CalDAV-backed) | completed/deleted items retained until account sync purge |

> 🔬 **Forensics note:** The recurring lesson is that an iOS "Delete" almost never means an immediate `DELETE FROM`. It means *flagged*, *moved to a recoverable join*, or *tombstoned* — pending a 30-day timer or a cloud sync. That timer is your evidence window: a full file-system acquisition taken inside it recovers the content as plain live rows; the same acquisition a month later finds the rows hard-deleted and you fall back to WAL/freelist carving. Acquire early.

> 🔬 **Forensics note:** Negative evidence still matters. Even with all the soft-delete planes, a *missing* `ROWID` in an otherwise contiguous sequence proves a record once existed and was hard-deleted. Sanderson's work on attributing recovered SMS shows you can sometimes still tie a carved/orphaned message part back to a handle via the surrounding intact rows. Always report the gaps, not just the recovered rows.

> ⚖️ **Authorization:** Recovered and soft-deleted content is still the subject's data and still inside your authorized scope's four corners. Recovering a *deleted* message does not expand your warrant — if the deleted item falls outside the authorized timeframe/custodian/subject-matter, it is no more admissible than a live one outside scope. Log the recovery method (flag-read vs. WAL-parse vs. carve) per item; defense will probe whether a "recovered" record is a real deletion or a parser artifact (a false positive from carving). Chain-of-custody and method-transparency are what make Plane 2–3 results survive a Daubert/Frye challenge.

### Which acquisition reaches which plane

Recovery ambition is bounded by the acquisition method — the planes you can touch depend entirely on *what you extracted and in what state*. Internalize this matrix:

| Acquisition | Plane 1 (soft-delete) | Plane 2 (WAL/journal) | Plane 3 (freelist/carve) | Plane 4 (FFS unallocated) |
|---|---|---|---|---|
| iTunes/Finder backup | ✅ (rows are in the backed-up DB) | ⚠️ only if sidecars were captured (often checkpointed pre-backup) | ⚠️ partial (freelist travels with the file) | ❌ no raw filesystem |
| Logical (libimobiledevice) | ✅ | ⚠️ same caveat | ⚠️ partial | ❌ |
| Full file-system (FFS) | ✅ | ✅ live `.sqlite` + `-wal`/`-shm` captured | ✅ | ✅ unallocated present in image |
| iCloud (no ADP) | ✅ | ❌ server-side, no sidecars | ❌ | ❌ |
| iCloud + **ADP** | ❌ (E2E-encrypted, undecryptable to you) | ❌ | ❌ | ❌ |
| BFU device | (only what's in class-D-decryptable files) | — | — | — |

The single highest-leverage fact: **only a full file-system acquisition gives you Planes 2–4.** A backup or logical pull hands you the database but routinely not its live, un-checkpointed sidecars, and never the surrounding unallocated space. If deleted-data recovery is the goal, push for FFS ([[full-file-system-acquisition]]) and capture lock-state AFU ([[bfu-vs-afu-and-data-protection-classes]]).

### What is genuinely gone

Recovery is not magic; three mechanisms make data unrecoverable in principle, not just in practice:

- **`VACUUM` / `PRAGMA secure_delete`.** A `VACUUM` rebuilds the database, compacting away freelist pages and freeblocks — Plane 3 is wiped. Some Apple databases run `auto_vacuum`; if `secure_delete` is on, freed bytes are zeroed on deletion, killing carving at the source. Check `PRAGMA secure_delete;` / `PRAGMA auto_vacuum;` on a copy to know what to expect.
- **Flash TRIM + APFS block reuse (Plane 4).** When the *whole file* is deleted, APFS frees its extents and the NAND controller's TRIM eventually erases those blocks for wear-leveling. Until that happens the bytes may be carvable from an FFS image; after it, they are physically gone. This is fundamentally less predictable than on a spinning disk — see [[storage-nand-aes-effaceable]].
- **Crypto-erase via effaceable storage (the real "gone").** This is the floor under all four planes. The key hierarchy: each file's contents are encrypted with a **per-file (per-extent) key** → wrapped by a **Data-Protection class key** (NSFileProtectionComplete, CompleteUntilFirstUserAuthentication, etc.) → those class keys live in the **system keybag**, wrapped by a key derived from the passcode *and* a hardware UID fused into the SEP → and the master secret that ultimately gates the lot is held in the SoC's **effaceable storage**, a small, dedicated, directly-addressable NAND region built precisely so it can be wiped fast and completely. *Erase All Content and Settings* destroys that effaceable key material in milliseconds; every wrapped key down the chain becomes undecryptable and the entire volume is instantly, irreversibly crypto-erased — no carving, no cold-boot, no recovery, regardless of what ciphertext physically remains on the NAND. This is also why a properly crypto-erased iPhone is *unrecoverable by design* where a quick-formatted hard drive is not. See [[data-protection-and-keybags]], [[sep-sepos-deep-dive]], and [[storage-nand-aes-effaceable]].

> 🔬 **Forensics note:** This is why the *acquisition method* gates the recovery question. Soft-deletes (Plane 1) survive even in an iTunes/Finder backup. WAL/freelist (Planes 2–3) survive in a **full file-system extraction** ([[full-file-system-acquisition]]) because you get the live `.sqlite` + sidecars. Whole-file unallocated carving (Plane 4) requires the rawest acquisition you can get and is defeated by Data-Protection-at-rest unless the file was decrypted at acquisition time. Crypto-erase defeats everything below it. Match your recovery ambitions to what the acquisition floor actually delivered.

### Tool taxonomy — which tool for which plane

No single tool covers all four planes; pick by plane and corroborate across tools (agreement between an independent WAL parser and a freelist carver is what hardens a finding):

| Tool | Primary plane(s) | Notes |
|---|---|---|
| `sqlite3` / `xxd` | 1, header inspection | Read soft-delete flags; read header offsets 18/32/36 to plan |
| iLEAPP (Brignoni) | 1, some 2 | Parses live + Recently-Deleted Photos/Messages and many WAL-resident artifacts into an HTML/CSV report |
| **walitean** (n0fate) | 2 | Independent `-wal` parser; rebuilds rows incl. stale frames |
| **SQLite Dissect** (DC3) | 2, 3 | Structured carve of main file + WAL/journal + freelist with signatures |
| **undark** (Daniels/inflex) | 3 | Dumps live + deleted rows to CSV; `--fine-search` for thorough scans |
| **sqlparse** (DeGrazia), **FQLite**, **bring2lite** | 3 | Freelist / unallocated / freeblock carvers; FQLite has a GUI; bring2lite is research-grade |
| **sqlite_miner** (Ciofeca) | cross-cutting | Finds + decompresses embedded gzip/zlib blobs (e.g. Notes `ZDATA` protobuf) |
| Forensic Browser for SQLite (Sanderson) | 1, 2, 3 | Commercial; presents WAL frames and recovered rows visually, reconstructs joins |
| Cellebrite PA / Magnet AXIOM / Belkasoft X | all + Plane 4 | Commercial suites; integrate FFS carving, WAL, freelist, and soft-delete parsing |
| `grep`/`bulk_extractor` + a carver | 4 | Hunt the `SQLite format 3` magic across an FFS image's unallocated space |

## Hands-on

There is no on-device shell; every command runs on the Mac against a copy (Simulator container, sample image, or extracted file set). **Copy-before-query, and copy the sidecars as a set.**

### Inspect the header to decide your strategy

```bash
# Is this WAL mode? (offset 18 == 02). Page size at offset 16. Freelist at 32/36.
xxd -l 48 sms.db
# 00000000: 5351 4c69 7465 2066 6f72 6d61 7420 3300  SQLite format 3.
# 00000010: 1000 0202 ...                            ^^^^ page size 0x1000=4096
#                ^^ write/read version 02 02  → WAL MODE: grab the sidecars
# 00000020: 0000 0000 0000 0000 ...                  freelist trunk=0, count=0 here
```

### Copy a database AND its sidecars (the only correct copy)

```bash
# Never copy the .sqlite alone. Copy the whole set.
for f in sms.db sms.db-wal sms.db-shm sms.db-journal; do
  [ -e "$f" ] && cp -p "$f" /evidence/sqlite/
done
ls -l /evidence/sqlite/        # confirm -wal/-shm came along; note sizes
```

### Read the soft-delete planes (no carving needed)

```bash
# Photos: assets sitting in Recently Deleted (Plane 1)
sqlite3 Photos.sqlite "
  SELECT ZUUID,
         ZFILENAME,
         datetime(ZTRASHEDDATE + 978307200,'unixepoch','localtime') AS trashed
  FROM ZASSET
  WHERE ZTRASHEDSTATE = 1
  ORDER BY ZTRASHEDDATE DESC;"

# Notes: notes flagged for deletion (Plane 1)
sqlite3 NoteStore.sqlite "
  SELECT Z_PK, ZTITLE1, ZMARKEDFORDELETION
  FROM ZICCLOUDSYNCINGOBJECT
  WHERE ZMARKEDFORDELETION = 1;"

# Messages (iOS 16+): join through the RECOVERABLE tables, not chat_message_join
sqlite3 sms.db "
  SELECT m.ROWID,
         datetime(m.date/1000000000 + 978307200,'unixepoch','localtime') AS msg_time,
         h.id AS handle, m.text
  FROM chat_recoverable_message_join crmj
  JOIN message m   ON m.ROWID = crmj.message_id
  LEFT JOIN handle h ON h.ROWID = m.handle_id
  ORDER BY m.date DESC;"
```

### Parse the WAL independently (Plane 2)

```bash
# walitean (n0fate): parse the -wal independently and export its frames to a queryable DB
git clone https://github.com/n0fate/walitean && cd walitean
#   -f  WAL file (required)   -x  output DB (required)   -m  main DB for schema (optional)
python3 walitean.py -f sms.db-wal -x recovered_from_wal.db -m sms.db
# Then diff the WAL-recovered rows against the live `message` table to find deletes-in-flight.
```

### Walk the WAL by hand (when tools choke on a malformed sidecar)

```bash
# WAL header: magic (4) · format (4) · pagesize (4) · checkpoint# (4) · salt1 (4) · salt2 (4) · csum1/2
xxd -l 32 sms.db-wal
# 00000000: 377f 0682 002d e218 0000 1000 0000 0003  → magic 377f0682, pagesize 0x1000
# 00000010: 7a1f 33c2 9b04 ab17 ...                  → salt-1, salt-2 (must match valid frames)

# Each frame = 24-byte frame header + one page (here 4096 bytes) → stride 4120 bytes.
# Frame header: page# (4) · db-size-after-commit (4, !=0 == COMMIT) · salt1 (4) · salt2 (4) · csum1/2 (8)
PS=4096; STRIDE=$((PS+24)); OFF=32
for i in 0 1 2 3; do
  printf 'frame %d @ %d: ' "$i" "$OFF"
  xxd -s "$OFF" -l 16 sms.db-wal | head -1     # page# + commit-size + salt — eyeball stale (salt mismatch) frames
  OFF=$((OFF+STRIDE))
done
# Frames whose salt-1/2 differ from the header's are STALE — superseded pages no live reader returns.
```

### Read the freelist trunk (Plane 3 entry point)

```bash
# File header offset 32 (4 bytes BE) = first freelist trunk page#; offset 36 = total freelist pages.
xxd -s 32 -l 8 sms.db
# 00000020: 0000 0017 0000 0009   → first trunk = page 0x17 (23); 0x09 (9) freelist pages total
# Each freelist trunk page begins: next-trunk-page# (4) · leaf-count (4) · leaf page#s ...
# Those leaf pages are whole freed b-tree pages — feed them to undark / SQLite Dissect to carve.
```

### Carve the freelist and unallocated cells (Plane 3)

```bash
# undark (inflex/pldaniels): dump every row it can validate, live AND deleted, to CSV
brew install undark   2>/dev/null || (git clone https://github.com/inflex/undark && cd undark && make)
undark -i sms.db --fine-search > sms_carved.csv
#   --fine-search  : shift one byte at a time (slower, finds more)
#   --rowsize-min / --cellcount-min : prune false positives once you know the schema

# DC3 SQLite Dissect: structured carve incl. WAL/journal + freelist, signature output
pip install sqlite-dissect
sqlite_dissect sms.db --carve --wal sms.db-wal -e csv -d /evidence/dissect_out/

# sqlite_miner (Ciofeca): hunt + auto-decompress embedded gzip/zlib blobs (e.g. Notes ZDATA)
python3 sqlite_miner.py --file NoteStore.sqlite
```

### Carve whole deleted databases from an FFS image (Plane 4)

```bash
# Hunt the SQLite magic across unallocated space of a full-file-system image
# (header at file offset 0 of each DB: "SQLite format 3\000")
grep -a -b -o "SQLite format 3" ffs_image.bin | head
#  ...byte offsets where a (possibly deleted) database header begins.
# Feed candidate offsets to a SQLite carver, or let iLEAPP/commercial suites do it:
python3 ileapp.py -t fs -i ./ffs_extraction/ -o ./ileapp_report/
#  iLEAPP parses live + Recently-Deleted Photos/Messages and many WAL-resident artifacts.
```

> ⚠️ **ADVANCED:** Running a carver with `--fine-search` over a multi-GB FFS image is I/O- and CPU-heavy and produces **false positives** — byte runs that validate as records but are coincidental. Treat every carved row as a *candidate* until corroborated (matching schema widths, plausible timestamps in the store's epoch, cross-reference to an intact neighbor). Never present a raw carve as fact.

## 🧪 Labs

> **Substrate note for this whole lesson.** The **Simulator** (Lab 1–3) gives you *real, current SQLite schemas* (`Photos.sqlite`, `NoteStore.sqlite`, the throwaway DB) sitting **unencrypted** on the Mac — perfect for learning soft-delete flags, the WAL, and the freelist. Its fidelity gap: there is **no SEP, no Data-Protection-at-rest, and no crypto-erase**, so the Simulator cannot teach you what is *genuinely gone* — Planes 1–3 are faithful, Plane 4 / effaceable-storage is not. For the device-only stores and real lock-state behavior, use a **public sample image** (Lab 4) where the device daemons (`knowledged`, `routined`, etc.) actually populated the stores.

### Lab 1 — Photos soft-delete (Simulator)

*Substrate: Simulator Photos. Fidelity: real `Photos.sqlite` schema; no device daemons, no encryption.*

1. Boot a Simulator and open Photos (it ships sample images). Delete one or two photos (they go to *Recently Deleted*).
2. Locate the container and copy the DB **with sidecars**:
   ```bash
   DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
   APP=~/Library/Developer/CoreSimulator/Devices/$DEV/data/Media/PhotoData
   cp -p "$APP"/Photos.sqlite* /tmp/photoslab/      # the * grabs -wal/-shm too
   ```
3. Run the `ZTRASHEDSTATE = 1` query from Hands-on. Confirm the photos you "deleted" are still rows. Convert `ZTRASHEDDATE` and check it matches when you deleted them.
4. Now empty *Recently Deleted* in the app, re-copy, and re-query. The rows are gone from `ZASSET` — proceed to Lab 3's carving technique to try to recover them from the freelist/WAL.

### Lab 2 — Notes soft-delete + compressed body (Simulator)

*Substrate: Simulator Notes. Fidelity: real `NoteStore.sqlite`; protobuf/gzip body identical to device.*

1. In the Simulator's Notes app, create a note with a distinctive sentence, then delete it.
2. Copy `NoteStore.sqlite*` from `.../data/Containers/Shared/AppGroup/<GUID>/` (find the GUID with `grep -rl group.com.apple.notes .../AppGroup/*/`).
3. Query `ZICCLOUDSYNCINGOBJECT WHERE ZMARKEDFORDELETION = 1` — your note should appear flagged, not removed.
4. Prove the no-secure-delete reality: `strings NoteStore.sqlite | grep -i "<your sentence>"`. Then run `python3 sqlite_miner.py --file NoteStore.sqlite` to decompress the `ZDATA` protobuf and recover the structured body.

### Lab 3 — WAL + freelist anatomy on a throwaway DB (Mac, no device)

*Substrate: a DB you build on the Mac. Fidelity: SQLite format is identical everywhere — this is the highest-fidelity lab in the lesson for the file format itself.*

1. Build and mutate a database, leaving the WAL un-checkpointed:
   ```bash
   cd /tmp && rm -f t.db*
   sqlite3 t.db "PRAGMA journal_mode=WAL;
                 CREATE TABLE msg(id INTEGER PRIMARY KEY, body TEXT);
                 INSERT INTO msg(body) VALUES('keep me'),('delete me'),('also keep');
                 DELETE FROM msg WHERE body='delete me';"
   ls -l t.db t.db-wal t.db-shm      # the sidecars exist; WAL is non-empty
   ```
2. Confirm WAL mode from the header (`xxd -l 20 t.db` → offset 18 == `02`) and dump the WAL header magic (`xxd -l 32 t.db-wal` → `377f0682`/`0683`).
3. Prove the deleted row survives the `SELECT` lie: `sqlite3 t.db "SELECT * FROM msg;"` shows only the two keepers — but `undark -i t.db --fine-search` (or `strings t.db t.db-wal`) recovers `delete me`.
4. Now checkpoint and watch the evidence collapse: `sqlite3 t.db "PRAGMA wal_checkpoint(TRUNCATE);"` then re-run `undark`. Observe how much harder recovery becomes after the WAL is merged — internalize *why you never checkpoint before parsing*.

### Lab 4 — device-only recovery on a public sample image (read-only walkthrough)

*Substrate: a public iOS reference image (Josh Hickman / Digital Corpora, or the iLEAPP test dataset). Fidelity: full — real device stores populated by real daemons, with real Recently-Deleted/WAL state the Simulator can't produce.*

1. Acquire a sample FFS extraction (Hickman's iOS images at thebinaryhick.blog, or `iLEAPP`'s bundled test data).
2. Run iLEAPP across the extraction: `python3 ileapp.py -t fs -i ./image_root -o ./report`. In the HTML report, find the **Recently Deleted** Photos and the iOS-16+ recoverable Messages sections — these are Plane-1 reads against device data.
3. Pick one artifact DB (e.g. `sms.db`) from the image, copy it **with its `-wal`/`-shm`**, and run `walitean` on the WAL and `undark` on the DB. Compare what each plane yields against iLEAPP's parsed output.
4. Write a one-paragraph recovery memo per item: which plane it came from, the method, and the corroboration. This is the deliverable that survives cross-examination.

### Lab 5 — the "wrong copy" failure drill (Mac, no device)

*Substrate: the Lab 3 throwaway DB. Fidelity: demonstrates the single most common real-world evidence-loss mistake.*

1. Rebuild a WAL-resident-delete DB as in Lab 3 (do **not** checkpoint).
2. Copy **only** `t.db` (omit the sidecars) to `/tmp/badcopy/`. Open it in a fresh `sqlite3` session and query `msg`.
3. Now copy the **full set** (`t.db t.db-wal t.db-shm`) to `/tmp/goodcopy/` and carve it. Diff the recoverable content between the two copies. Quantify exactly what the sidecar-less copy lost — then never make that copy again.

## Pitfalls & gotchas

- **Copying the `.sqlite` without its `-wal`/`-shm`.** The cardinal sin. You silently drop the newest rows (including just-deleted ones) and can trigger a checkpoint/new-WAL that destroys evidence on first open. Copy the set; better, image the whole app container.
- **Checkpointing or `VACUUM`-ing before you parse.** Both collapse the recovery planes. Checkpoint merges WAL history away; `VACUUM` compacts the freelist/freeblocks away. Parse the WAL and carve the freelist on an untouched copy *first*.
- **Reaching for a carver before reading the soft-delete flags.** Recently-Deleted Photos (`ZTRASHEDSTATE`), flagged Notes (`ZMARKEDFORDELETION`), and iOS-16+ recoverable Messages are **live rows** — you read them, you don't carve them. Carving when a simple flag-read would do wastes time and invites false positives.
- **Wrong epoch on a recovered timestamp.** Apple stores use **Mac Absolute Time** (epoch 2001-01-01; add `978307200`). The Messages `date` column is *nanoseconds* since that epoch on modern iOS (`/1000000000` first, then add the offset). A carved row whose timestamp lands in 1970 or 2055 is an epoch-conversion error, not a real artifact. See [[the-ios-timestamp-zoo]].
- **Schema drift across iOS versions.** `ZGENERICASSET`→`ZASSET` (iOS 14), the introduction of `chat_recoverable_message_join`/`recoverable_message_part` (iOS 16), Biome/SEGB displacing knowledgeC (iOS 17). Always `.schema` the actual database; never hardcode column names from a blog post against a different OS version.
- **`secure_delete` / `auto_vacuum` already burned the freelist.** Some stores zero freed bytes or compact automatically. Check the pragmas on a copy before promising freelist recovery — if `secure_delete=1`, Plane 3 is empty by design.
- **Treating carved candidates as confirmed.** Carving validates *structure*, not *truth*. A byte run can validate as a record by coincidence. Corroborate every carved row (schema widths, plausible epoch, intact neighbors) before it goes in a report.
- **Forgetting the acquisition floor.** No amount of carving recovers what was never decrypted. A BFU device, an ADP-protected cloud set, or a crypto-erased volume yields nothing below Plane 1 — and Plane 1 only if you have the live file. Recovery ambition must match acquisition reality ([[bfu-vs-afu-and-data-protection-classes]], [[full-file-system-acquisition]]).
- **The Simulator can't teach "gone."** It has no SEP, no Data-Protection, no effaceable storage — so it will happily let you "recover" things a real device would have crypto-erased. Use it for schema and format; use sample images for lock-state and true-deletion behavior.
- **iCloud-synced soft-deletes can vanish remotely mid-investigation.** A `ZMARKEDFORDELETION` note, a Recently-Deleted photo, or a recoverable message can be purged by a cloud sync *after* you image if the account stays online — and the 30-day timers keep ticking. Put the device in airplane mode / a Faraday bag at seizure and snapshot the soft-delete planes immediately; do not assume next week's re-pull will still have them.
- **Hashing the database without its sidecars breaks integrity claims too.** If you hash only `sms.db` but analysis depended on `sms.db-wal`, your integrity record doesn't cover the evidence you actually used. Hash every file in the set.

## Key takeaways

- "Deleted" on iOS is a **question with four answers**: a soft-delete flag (live row), a pre-checkpoint WAL frame, a freelisted/freeblocked record, or unallocated filesystem — work them top-down, cheapest and highest-fidelity first.
- **Read offset 18 of the SQLite header** to know if it's WAL mode, and offsets 32/36 to see if a freelist exists, *before* you query anything.
- **Copy databases as a set** — `.sqlite` + `-wal` + `-shm` (+ `-journal`) — and never checkpoint or `VACUUM` before parsing; both collapse the recovery planes.
- **Soft-deletes are reads, not recoveries:** `ZTRASHEDSTATE=1` (Photos), `ZMARKEDFORDELETION=1` (Notes), and `chat_recoverable_message_join`/`recoverable_message_part` (Messages, iOS 16+) hold the data in plain, queryable rows.
- **SQLite never scrubs on delete** (absent `secure_delete`): freeblock chains and freelist pages keep the original record bytes, and the self-describing serial-type record format makes them carvable with undark / SQLite Dissect / sqlparse / FQLite.
- **Negative evidence counts:** a gap in a `ROWID` sequence proves a hard-deletion happened even when no content survives.
- **The genuinely-gone set is small and specific:** `VACUUM`/`secure_delete`, TRIM-reclaimed APFS extents, and — the real floor — **crypto-erase via effaceable storage**, which makes every file key undecryptable in milliseconds.
- **A `SELECT` is a write:** opening a live database can create a `-shm`, extend a `-wal`, or trigger a checkpoint/`VACUUM` that destroys recoverable frames — image first, copy the full sidecar set, hash every file, then query the copy.
- **Corroborate across planes and tools:** agreement between an independent WAL parser (walitean) and a freelist carver (undark/SQLite Dissect), plus a sane epoch and an intact neighbor, is what turns a carved candidate into a defensible finding.
- The technique is **identical to macOS SQLite recovery**; what changes on iOS is the *acquisition floor underneath* (Data-Protection class keys and lock state decide whether you even have the decrypted file).

## Terms introduced

| Term | Definition |
|---|---|
| Write-Ahead Log (WAL) | SQLite durability mode (default on iOS) that appends new page images to a `<db>-wal` sidecar; pre-checkpoint, it holds the newest rows — including just-deleted ones — that the main file does not yet reflect |
| `-shm` (shared-memory index) | The `<db>-shm` wal-index file mapping each page to its current WAL frame; must be preserved with the database to resolve WAL state |
| Checkpoint | The operation that merges WAL frames into the main database file, collapsing superseded (recoverable) page images — never run it before parsing |
| Stale WAL frame | A WAL frame whose salts don't match the current header; a committed-then-superseded page image no live reader returns — high-value for recovery |
| Freelist | A chain of trunk/leaf pages (rooted at file-header offset 32) listing whole pages freed by deletions; freed pages retain their old, unscrubbed cell content |
| Freeblock | An unlinked-but-unscrubbed cell span inside a b-tree page (chained from page-header bytes 1–2); the original record bytes persist until overwritten |
| Serial-type record format | SQLite's self-describing record encoding (header of per-column type varints + bodies) that lets carvers validate and decode deleted rows from unallocated space |
| Soft-delete | An app-level "deletion" that only sets a flag (`ZTRASHEDSTATE`, `ZMARKEDFORDELETION`) or moves a join, leaving the row live and fully queryable |
| `ZTRASHEDSTATE` | `Photos.sqlite` `ZASSET` column: `1` = asset is in Recently Deleted (30-day trash), not removed |
| `ZMARKEDFORDELETION` | `NoteStore.sqlite` `ZICCLOUDSYNCINGOBJECT` column flagging a note as deleted-but-present until sync purge |
| `chat_recoverable_message_join` / `recoverable_message_part` | iOS-16+ `sms.db` tables implementing the Messages Recently-Deleted (30-day) trash; deleted iMessages are recovered by joining through these |
| `secure_delete` / `VACUUM` | SQLite mechanisms that zero freed bytes / rebuild-and-compact the file respectively — each destroys a recovery plane |
| Crypto-erase | Irreversible data destruction by deleting the key, not the data; on iOS, *Erase All Content and Settings* destroys the Data-Protection root keys in effaceable storage, instantly making every file undecryptable |
| Effaceable storage | A small, directly-addressable NAND region holding the keys that root the Data-Protection hierarchy; wiping it crypto-erases the whole volume |
| undark | Open-source (Paul L. Daniels / inflex) command-line SQLite carver that dumps live and deleted rows from a database to CSV |
| walitean | Open-source (n0fate) tool that parses a `-wal` file independently and reconstructs its rows, including stale frames |
| sqlite_miner | Open-source (Ciofeca Forensics) tool that hunts and auto-decompresses embedded gzip/zlib blobs (e.g. Notes `ZDATA`) inside SQLite files |
| SQLite Dissect | DC3 (DoD Cyber Crime Center) carver that structurally recovers records from the main file, WAL/journal, and freelist with signatures |

## Further reading

- Paul Sanderson, *SQLite Forensics* / Sanderson Forensics — "Forensic examination of SQLite Write Ahead Log (WAL) files," "Recovering deleted records from an SQLite database," "SMS recovered records and contacts," and the **Forensic Browser for SQLite** (sqliteforensictoolkit.com)
- Belkasoft — "Forensic Analysis of SQLite Databases: Free Lists, Write Ahead Log, Unallocated Space and Carving" (belkasoft.com/sqlite-analysis)
- SQLite.org primary docs — *Database File Format*, *Write-Ahead Logging* (sqlite.org/wal.html), *WAL-mode File Format* (sqlite.org/walformat.html), *Record Format*
- Tools — `undark` (github.com/inflex/undark, pldaniels.com/undark), `walitean` (github.com/n0fate/walitean), `sqlite_miner` (Ciofeca Forensics), Mari DeGrazia's **sqlparse / SQLite Deleted Records Parser**, **FQLite**, **bring2lite** (DFRWS 2019), **DC3 SQLite Dissect** (github.com/dod-cyber-crime-center/sqlite-dissect)
- Scott Koenig, *The Forensic Scooter* — `Photos.sqlite` query documentation, `ZTRASHEDSTATE`/`ZTRASHEDDATE`, and schema-version notes (theforensicscooter.com)
- `apple_cloud_notes_parser` (github.com/threeplanetssoftware) and Ciofeca Forensics' Apple Notes series — `NoteStore.sqlite` protobuf/gzip decoding and `ZMARKEDFORDELETION`
- Alexis Brignoni — **iLEAPP** (github.com/abrignoni/iLEAPP); Sarah Edwards (mac4n6.com) — iOS SQLite artifact research; Josh Hickman (thebinaryhick.blog) / Digital Corpora — public iOS reference images
- "A comprehensive analysis and evaluation of SQLite deleted Record recovery techniques: A survey" (ScienceDirect, 2025) — taxonomy of metadata/carving/WAL-based recovery
- Apple Platform Security Guide — Data Protection class keys, effaceable storage, and crypto-erase on *Erase All Content and Settings*
- `man sqlite3`, `PRAGMA journal_mode` / `PRAGMA secure_delete` / `PRAGMA auto_vacuum` / `PRAGMA wal_checkpoint`

---
*Related lessons: [[communications-imessage-and-sms]] | [[photos-and-the-camera-roll]] | [[mail-notes-calendar-reminders]] | [[full-file-system-acquisition]] | [[bfu-vs-afu-and-data-protection-classes]] | [[storage-nand-aes-effaceable]] | [[the-ios-timestamp-zoo]] | [[correlation-and-anti-forensics]]*
