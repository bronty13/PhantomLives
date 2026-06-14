# Changelog

All notable changes to `apple-archiver` are recorded here.

## 1.0.0 — 2026-06-14

Initial release — permanent, append-only, browsable archives of Apple Notes and
Apple Reminders (the Notes/Reminders analogue of the photo + Messages archives).
Standard-library Python only.

- **`notes_archiver.py`** — archives `NoteStore.sqlite`. Decodes the
  gzip-compressed protobuf note bodies (`ZICNOTEDATA.ZDATA`) with a small
  pure-Python protobuf walker (no `protobuf` dep). Resolves folders + creation/
  modification dates (COALESCE across macOS schema variants). Outputs per-folder
  `.md` notes + searchable `notes.html` + `_index.csv`.
- **`reminders_archiver.py`** — archives the Reminders Core Data store(s)
  (`ZREMCDREMINDER` + `ZREMCDBASELIST`); scans every `Data-*.sqlite` under a
  `Stores` directory. Outputs per-list `.md` (Open/Completed, due/priority/flag/
  notes) + searchable `reminders.html` + `_index.csv`.
- **Append-only + versioned:** `manifest.jsonl` keeps one line per *version* of
  each item (id + content-hash); edits, completions, and deletions on the source
  are preserved forever. Views are regenerated from the latest version each run.
- Shared helpers in `applearchive_common.py`; 7 tests in `test_apple_archiver.py`
  (synthetic DBs: protobuf decode, idempotency, versioning-on-edit/completion,
  deleted-note preservation, list status).
- Validated on real data (this Mac): 236 notes, 6,468 reminders across 9 lists.
