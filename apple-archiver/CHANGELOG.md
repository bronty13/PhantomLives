# Changelog

All notable changes to `apple-archiver` are recorded here.

## 1.5.0 — 2026-06-14 (polish)

### Added
- **Notes attachments.** `notes_archiver.py` now links each note's embedded
  attachments (images/scans/audio/files): it joins the attachment rows
  (`ZNOTE`→note, `ZMEDIA`→media object) to the on-disk `Media/<uuid>/…` files
  (mirrored into the archive's `media/`) and embeds them in `notes.html` (inline
  `<img>`, `<audio>` players, file links) + lists them in each note's Markdown.
  Versioned (a changed attachment set bumps the note version). Verified on real
  data: 177 attachments (31 images + 146 audio + files).
- **`archive_index.py`** — a per-source landing page (`<Name>-Archives.html`)
  linking every archive's browsable views + raw files, with item counts.
- Tests grew to 25.

## 1.4.0 — 2026-06-14 (Phase 3, small wins)

### Added
- **`podcasts_archiver.py`** — Apple Podcasts subscriptions from MTLibrary.sqlite
  (`ZMTPODCAST` + per-show `ZMTEPISODE` counts): title, author, category, feed,
  website, subscribed flag → podcasts.html + _index.csv. Verified: 11 shows.
- **`stickies_archiver.py`** — Stickies notes from `.rtfd` bundles; text via macOS
  `textutil` (pure-Python RTF-strip fallback). Per-sticky .txt + stickies.html.
  The .rtfd bundles are preserved separately (rsynced). Verified: 2 notes.
- Tests grew to 23.

### Not built (no readable/local data)
- **Freeform** (no container on the test/source Macs), **Maps favorites** (iCloud-
  encrypted, no local store). Reserved in ROADMAP — build when a source has them.

## 1.3.0 — 2026-06-14 (Phase 2)

### Added
- **`calendar_archiver.py`** — Apple Calendar events from `Calendar.sqlitedb`
  (modern `CalendarItem`+`Calendar`+`Location` schema). Per calendar: a Markdown
  agenda, a browsable `calendar.html`, and a **re-importable `.ics`** (in `ics/`)
  with VEVENTs (all-day → `VALUE=DATE`), plus `_index.csv`. Events versioned by
  content. Verified: 2,543 events / 7 calendars on this Mac.
- **`books_archiver.py`** — Apple Books highlights + notes from
  `AEAnnotation/AEAnnotation*.sqlite` (`ZAEANNOTATION`, skips deleted) joined to
  titles/authors in `BKLibrary/BKLibrary*.sqlite` (`ZBKLIBRARYASSET`). Per-book
  Markdown + a collapsible searchable `books.html` (highlight color from
  `ZANNOTATIONSTYLE`) + `_index.csv`. Highlights versioned by content.
- Tests grew to 18.

## 1.2.2 — 2026-06-14

### Added
- **Call history metadata enrichment.** Uses `ZSERVICE_PROVIDER` (Phone vs
  FaceTime) and `ZISO_COUNTRY_CODE` (e.g. US) so the log is informative even when
  the number is `(encrypted)`. New `country` column in calls.csv.
- **Decryption placeholder.** `decrypt_address()` documents the (encrypted-at-rest)
  situation and reserves a hook for a future on-Mac, framework-based decryption
  path; currently returns None → `(encrypted)`.

## 1.2.1 — 2026-06-14

### Fixed
- **Call history: handle encrypted `ZADDRESS`/`ZNAME`.** On some macOS versions
  (notably ≤12) these are encrypted blobs, not plaintext; the archiver was dumping
  raw bytes into calls.csv/html. Now shows `(encrypted)` for unreadable values
  while still preserving the plaintext call metadata (date, direction, duration,
  answered/missed, kind). The number itself can't be recovered from a pulled DB
  (the key lives in the source Mac's keychain).

## 1.2.0 — 2026-06-14

### Added — Tier 1: Safari, Voice Memos, Call history
- **`safari_archiver.py`** — Safari history (immutable visit events from
  `History.db`) + bookmarks + reading list (from `Bookmarks.plist`, versioned).
  Outputs `history.html`/`.csv` (HTML caps to the most-recent 4,000; full set in
  CSV), `bookmarks.html`/`.csv`, `readinglist.html`.
- **`voicememos_archiver.py`** — **file-driven** index of Voice Memos: every
  `.m4a` becomes a memo (date parsed from the filename), enriched by
  `CloudRecordings.db` title/duration when present (the DB is often empty). Builds
  `voicememos.html` with inline `<audio>` players + `_index.csv`. The audio files
  themselves are preserved separately (rsynced into `recordings/`).
- **`callhistory_archiver.py`** — phone + FaceTime call log from
  `CallHistory.storedata` (`ZCALLRECORD`), immutable events. `calls.html` (in/out/
  missed, duration, contact name) + `calls.csv` + per-number `_index.csv`.
- Tests grew to 13 (synthetic History.db + Bookmarks.plist, ZCALLRECORD, m4a files).

## 1.1.0 — 2026-06-14

### Added
- **Reminders HTML is now collapsible + filterable.** Each reminder is a
  collapsible `<details>` (summary = checkbox/title/meta; expand for notes +
  completion/created dates), each list is a collapsible section, and a **"Hide
  completed"** toggle hides done items. Plus Expand-all / Collapse-all buttons and
  the existing live text filter. (`reminders_archiver.py` 1.0.0 → 1.1.0.)

## 1.0.0 — 2026-06-14

Initial release — permanent, append-only, browsable archives of Apple Notes and
Apple Reminders (the Notes/Reminders analogue of the photo + Messages archives).
Standard-library Python only.

- **`notes_archiver.py`** — archives `NoteStore.sqlite`. Decodes the
  gzip-compressed protobuf note bodies (`ZICNOTEDATA.ZDATA`) with a small
  pure-Python protobuf walker (no `protobuf` dep). Resolves folders + creation/
  modification dates (COALESCE across macOS schema variants). Outputs per-folder
  `.md` notes + searchable `notes.html` + `_index.csv`.
- **`reminders_archiver.py`** — archives the Reminders Core Data store(s); scans
  every `Data-*.sqlite` under a `Stores` directory. **Version-robust across two
  schemas**: modern (macOS 13+: `ZREMCDREMINDER` + `ZREMCDBASELIST`, title
  `ZTITLE`/created `ZCREATIONDATE`/list `ZNAME`) and legacy (macOS ≤12:
  `ZREMCDOBJECT`, title `ZTITLE1`/created `ZCREATIONDATE1`/list `ZNAME2`) — column
  variants are detected per-table and COALESCEd. Outputs per-list `.md`
  (Open/Completed, due/priority/flag/notes) + searchable `reminders.html` + `_index.csv`.
- **Append-only + versioned:** `manifest.jsonl` keeps one line per *version* of
  each item (id + content-hash); edits, completions, and deletions on the source
  are preserved forever. Views are regenerated from the latest version each run.
- Shared helpers in `applearchive_common.py`; 8 tests in `test_apple_archiver.py`
  (synthetic DBs: protobuf decode, idempotency, versioning-on-edit/completion,
  deleted-note preservation, list status, legacy `ZREMCDOBJECT` schema).
- Validated on real data: this Mac (Sonoma) 236 notes / 6,468 reminders; a
  Monterey source (legacy schema) 19 notes / 2,720 reminders across 6 lists.
