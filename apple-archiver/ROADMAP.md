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

## Phase 3 — small wins shipped (2026-06-14)

| Kind | Source store | Archiver |
|---|---|---|
| Podcasts | `MTLibrary.sqlite` (`ZMTPODCAST`/`ZMTEPISODE`) | `podcasts_archiver.py` |
| Stickies | `.rtfd` bundles (`textutil` → text) | `stickies_archiver.py` |

**Not built** — no readable/local data on the test or source Macs: **Freeform**
(no container present), **Maps** favorites/guides (iCloud-encrypted, no local
store). Reserved — add when a source actually has them.

## Phase 3 — the big one — SHIPPED (2026-06-14)

- **Mail** (`mail_archiver.py`) — additive rsync of `~/Library/Mail/V<n>/` (no `--delete`)
  + `.emlx` parse (stdlib `email`): byte-count line → RFC-2822 → flags plist; `.partial.emlx`
  attachments rejoined from the sibling `Data/Attachments/<num>/` tree. Per message: a
  re-importable `.eml`, a readable HTML render, extracted attachments (collision-safe), a
  sortable `mail.html` + `_index.csv` grouped by account/mailbox. Manifest keyed by
  account+mailbox+msgnum (incremental, idempotent; deletions preserved). **Verified on
  Rachel's Monterey Mac: 3,633 messages / 2 accounts / 342 attachments / 0 unparseable.**
  Gated by `mail.enabled` → `SRC_MAIL_ENABLED`; launchd `external-mail-sync.<id>`.

## Call-history decryption — investigated, concluded (2026-06-14)

Done. Full writeup in **`DECRYPTION.md`**. The numbers are AES-GCM encrypted with a
login-keychain key released only to an interactive GUI session — **offline/pulled-DB
decryption is impossible**. Proven over SSH: the framework returns every call but
blank addresses ("User interaction is not allowed"). An opt-in
**`calls_decrypt_helper.py`** (run in the source's GUI session) can recover numbers
and `callhistory_archiver.py --decrypted` folds them in; left **disabled** because it
puts a running component on the source Mac and the practical payoff is only
*call-only* numbers (texted contacts' numbers are already in Messages + Contacts).
**Decision pending** from the maintainer on whether to enable it.

## Polish backlog
- Top-level `index.html` landing page linking every source's sub-archives.
- ~~Notes attachments~~ (done, 1.5.0).

## Adding a source / kind (the pattern)

1. New `<kind>_archiver.py` in this folder (stdlib-only; reuse `applearchive_common`).
2. `external-<kind>-sync.sh <id>` operational script (snapshot/pull → run archiver).
3. `<kind>.enabled` flag in `external-sources.json`; expose `SRC_<KIND>_ENABLED` in
   `source-vars.py`.
4. Add the token to PurpleMirror's `JobRegistry.externalKinds` and a `status-check.sh`
   section. Install the per-source launchd job. No source name goes in any committed code.
