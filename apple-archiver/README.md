# apple-archiver

**Current release: 1.4.0**

Permanent, append-only, **browsable** archives of **Apple Notes** and **Apple
Reminders** — the Notes/Reminders analogue of PhantomLives's photo + Messages
archives. Standard-library Python only (no third-party deps), so it runs against
a *pulled* snapshot of a source Mac's databases on any Mac.

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

## Where the data lives (macOS)

- Notes: `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`
- Reminders: `~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-*.sqlite`

Both are Full-Disk-Access protected. In the PurpleAttic pull model these are
snapshotted on the source Mac and pulled to the archiving host; see the
operational `external-notes-sync.sh` / `external-reminders-sync.sh` scripts,
which are driven by the same `external-sources.json` (`notes.enabled` /
`reminders.enabled` per source) and surface in **PurpleMirror**.

## Tests

```bash
./run-tests.sh        # python3 test_apple_archiver.py — synthetic DBs, 7 tests
```

## Not yet archived (future)

- Note **attachments** (embedded images/drawings/scans) — currently text only.
- Reminders **subtasks / attachments / recurrence rules**.
