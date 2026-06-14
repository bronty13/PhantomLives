# apple-archiver roadmap

Per-source Apple-data archives, all on the same PurpleAttic **pull model**
(snapshot the source Mac's on-disk store → archive on the host → append-only
`manifest.jsonl` + browsable views → `external-<kind>-sync.<id>` launchd job that
**PurpleMirror** auto-groups under the source). Each is gated by a flag in
`external-sources.json` (`<kind>.enabled`).

## Phase 1 — shipped (2026-06-14)

| Kind | Source store | Archiver |
|---|---|---|
| Photos | `osxphotos` export | (PurpleAttic core) |
| Messages | `chat.db` + `Attachments/` | `messages-exporter` |
| Notes | `NoteStore.sqlite` (gzip-protobuf bodies) | `notes_archiver.py` |
| Reminders | `ZREMCDREMINDER`/`ZREMCDOBJECT` (modern + legacy) | `reminders_archiver.py` |
| Safari | `History.db` + `Bookmarks.plist` | `safari_archiver.py` |
| Voice Memos | `.m4a` files + `CloudRecordings.db` | `voicememos_archiver.py` |
| Call history | `CallHistory.storedata` (`ZCALLRECORD`) | `callhistory_archiver.py` |

## Phase 2 — shipped (2026-06-14)

| Kind | Source store | Archiver |
|---|---|---|
| Calendar | `Calendar.sqlitedb` (13+) / `Calendar Cache` `ZCALENDARITEM` (≤12) | `calendar_archiver.py` — Markdown + HTML + **`.ics`** |
| Books | `AEAnnotation*.sqlite` + `BKLibrary*.sqlite` | `books_archiver.py` — per-book highlights MD + collapsible HTML |

Both dual-schema / version-robust (column introspection + COALESCE), same as
Reminders. Verified: Calendar 1,943 events on a Monterey source; Books schema +
synthetic tests (no highlights on the test Macs yet).

## Phase 3 — later / heavier

- **Mail** — `~/Library/Mail/` `.emlx` messages (+ attachments). Highest volume
  and complexity; likely an additive rsync of the maildir-ish tree + a parsed
  index (sender/subject/date/folder) rather than full re-render. The
  `messages-exporter` already covers the highest-value conversational data, so
  this is lower priority.
- **Candidates** (smaller, opportunistic): Freeform boards
  (`~/Library/Containers/com.apple.freeform`), Stickies, Podcasts subscriptions,
  News saved stories, Maps favorites/guides, Shortcuts.

## Adding a source / kind (the pattern)

1. New `<kind>_archiver.py` in this folder (stdlib-only; reuse `applearchive_common`).
2. `external-<kind>-sync.sh <id>` operational script (snapshot/pull → run archiver).
3. `<kind>.enabled` flag in `external-sources.json`; expose `SRC_<KIND>_ENABLED` in
   `source-vars.py`.
4. Add the token to PurpleMirror's `JobRegistry.externalKinds` and a `status-check.sh`
   section. Install the per-source launchd job. No source name goes in any committed code.
