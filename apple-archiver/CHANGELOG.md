# Changelog

All notable changes to `apple-archiver` are recorded here.

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
