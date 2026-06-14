# apple-archiver

**Current release: 1.7.0**

Permanent, append-only, **browsable** archives of a Mac's Apple data — the
Notes/Mail/etc. analogue of PhantomLives's photo + Messages archives.
Standard-library Python only (no third-party deps), so it runs against a *pulled*
snapshot of a source Mac's databases/stores on any Mac.

**Archivers** (each `<kind>_archiver.py`, gated by `<kind>.enabled` in
`external-sources.json`, surfaced in **PurpleMirror**): Notes · Reminders · Safari ·
Voice Memos · Call history (with opt-in number decryption — see `DECRYPTION.md`) ·
Calendar (+ re-importable `.ics`) · Books · Podcasts · Stickies · **Mail** (+
re-importable `.eml`). `archive_index.py` builds a per-source landing page linking
them all.

Same preservation model as the rest of PurpleAttic's external-source archives:

- **Source of truth (append-only, never rewritten):** `manifest.jsonl` — one JSON
  line per *version* of an item, keyed by `id` + content-hash. Notes and
  reminders are **mutable**, so a new line is appended whenever an item's content
  changes. Edits, completions, and **deletions on the source device are preserved
  forever** — nothing is ever lost.
- **Derived views (regenerated each run from the latest version of each item):**
  human-readable text + HTML + a CSV index.

## Notes — `notes_archiver.py`

```bash
notes_archiver.py --db <NoteStore.sqlite> --archive <dir>
```

Reads `NoteStore.sqlite` (`ZICCLOUDSYNCINGOBJECT` + `ZICNOTEDATA`). Note bodies are
a **gzip-compressed protobuf** in `ZICNOTEDATA.ZDATA`; a small pure-Python
protobuf walker decodes them to text (no `protobuf` package needed). Outputs:

- `notes/<Folder>/<title>__<id>.md` — title + metadata header + body.
- `notes.html` — searchable list linking to each note.
- `_index.csv` — title / folder / created / modified / versions / deleted.

## Reminders — `reminders_archiver.py`

```bash
reminders_archiver.py --db <Stores dir or Data-*.sqlite> --archive <dir>
```

Reads the Reminders Core Data store(s) (`ZREMCDREMINDER` joined to
`ZREMCDBASELIST`) — pass the `…/group.com.apple.reminders/Container_v1/Stores`
directory and it scans every `Data-*.sqlite`. Outputs:

- `reminders/<List>.md` — Open + Completed sections (`[ ]`/`[x]`, due dates,
  priority, flags, notes).
- `reminders.html` — searchable, grouped by list, completed struck through.
- `_index.csv` — list / open / completed / total.

## Mail — `mail_archiver.py`

```bash
mail_archiver.py --mail-store <…/Library/Mail/V9> --archive <dir>
```

Walks a pulled `~/Library/Mail/V<n>/` (V9 = macOS 12) for `*.emlx`/`*.partial.emlx`.
Each `.emlx` is a leading byte-count line + the raw RFC-2822 message + a trailing
flags plist; the stdlib `email` module parses the message, and `.partial.emlx`
attachments are rejoined from the sibling `Data/Attachments/<num>/` tree. Outputs:

- `messages/<Account>/<Mailbox>/<subject>__<id>.eml` — **re-importable** raw message.
- `messages/<Account>/<Mailbox>/<subject>__<id>.html` — readable render (headers +
  body + inline images), with attachments extracted (collision-safe) to
  `attachments/<id>/`.
- `mail.html` — searchable index (newest first); `_index.csv` — date / from /
  subject / account / mailbox / attachments.

Manifest is keyed by account + mailbox + message number (emails are immutable →
incremental + idempotent; messages deleted on the source stay archived). The whole
Mail tree is additively `rsync`'d first (no `--delete`) as a byte-for-byte safety net.

## Where the data lives (macOS)

- Notes: `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`
- Reminders: `~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-*.sqlite`
- Mail: `~/Library/Mail/V<n>/` (V9 on macOS 12)

All are Full-Disk-Access protected. In the PurpleAttic pull model these are
snapshotted/rsync'd on the source Mac and pulled to the archiving host; see the
operational `external-<kind>-sync.sh` scripts, driven by the same
`external-sources.json` (`<kind>.enabled` per source) and surfaced in **PurpleMirror**.

## Tests

```bash
./run-tests.sh        # python3 test_apple_archiver.py — synthetic DBs, 31 tests
```

## Not yet archived (future)

- Reminders **subtasks / attachments / recurrence rules**.
- Freeform / Maps (no readable local store on the test Macs yet).
