---
title: "Mail, Notes, Calendar & Reminders"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 09
est_time: "45 min read + 20 min labs"
prerequisites: [app-sandbox-and-filesystem-layout]
tags: [ios, forensics, notes, mail, calendar, reminders, dfir]
last_reviewed: 2026-06-26
---

# Mail, Notes, Calendar & Reminders

> **In one sentence:** The four productivity stores are where the *smoking gun* usually lives — a passcode jotted in Notes, an alibi-breaking event in Calendar, a deleted email still sitting in `Trash`, a geofenced reminder that places a person at an address — and reading them means decompressing a GZIP'd protobuf, decoding a Core Data entity table, and tracking the iCloud-vs-local provenance of every row before you trust a tool's tidy export.

## Why this matters

Messages, call logs, and location get the attention, but in real casework the deciding evidence is disproportionately found in the "boring" productivity apps. People treat Notes as a private scratchpad and put passwords, account recovery codes, drug ledgers, and confession-grade free text in it. Calendar records **intent and presence** — a person deliberately scheduled themselves to be somewhere, with a place name and other attendees attached. Mail carries the documentary trail. Reminders, since it gained location triggers, quietly stores street addresses tied to a "when I get here" geofence. None of these are difficult formats, but each has a specific trap: the Notes body is a gzipped protobuf (a plain `SELECT` returns a useless blob), iOS Mail splits content across an `Envelope Index` and a separate `Protected Index` plus per-message `.emlx` files, and Reminders is raw Core Data where the table names are abstract entities you must demultiplex through `Z_PRIMARYKEY`. This lesson is the on-disk reality of all four, at the level where you can extract a note's plaintext by hand and defend every timestamp.

## Concepts

### The four stores at a glance

All four are SQLite (Reminders and Notes via Core Data; Calendar a hand-rolled relational schema; Mail a hybrid of two SQLite indexes plus a tree of MIME files). On a real device every one of them is **Data-Protection-class encrypted at rest** — typically `NSFileProtectionCompleteUntilFirstUserAuthentication` (Class C), so they are readable in an **AFU** acquisition but opaque in **BFU**. (See [[02-bfu-vs-afu-and-data-protection-classes]].)

| App | Primary store | On-device path (`/private/var/mobile/...`) | Format | Owning framework |
|---|---|---|---|---|
| Notes | `NoteStore.sqlite` | `Containers/Shared/AppGroup/<UUID>/NoteStore.sqlite` | Core Data SQLite; note body = GZIP'd protobuf blob | `notesd` / CloudKit |
| Mail | `Envelope Index` + `Protected Index` + `.emlx` | `Library/Mail/` (and a `Containers/Data/Application/<GUID>/` for the app) | Two SQLite indexes + MIME message files | `MailKit` / `mailagent` |
| Calendar | `Calendar.sqlitedb` | `Library/Calendar/Calendar.sqlitedb` | Relational SQLite (EventKit backing store) | `EventKit` / `calaccessd` |
| Reminders | `Data-<UUID>.sqlite` | `Library/Reminders/Container_v1/Stores/` *(also a `group.com.apple.reminders` group container)* | Core Data SQLite | `EventKit` (`remindd`) |

Each of these is a WAL-mode database. As with `sms.db` in [[04-communications-imessage-and-sms]], the `-wal` and `-shm` sidecars are part of the evidence — copy the triplet, never let a client checkpoint the original, and carve the WAL for deleted rows before any tool folds it back.

> 🖥️ **macOS contrast:** You already dissected the **exact same formats** in macOS Mastery. `NoteStore.sqlite` (gzip-protobuf `ZICNOTEDATA.ZDATA`), the Mail `Envelope Index` + `.emlx` tree, and `Calendar.sqlitedb` are **byte-for-byte the same schemas** on the Mac — only the path roots differ (`~/Library/Group Containers/group.com.apple.notes/` and `~/Library/Mail/` and `~/Library/Calendar/`). The frameworks (`EventKit`, the Notes protobuf, MailKit's index split) are shared code. If a suspect runs Continuity + iCloud, the Mac is a **second copy of all four stores**, frequently AFU/FileVault-unlocked when the phone is locked — often your fastest path to the same content.

> ⚖️ **Authorization:** These stores routinely contain third-party PII (other people's emails, phone numbers, addresses, calendar invitees) and privileged/medical/legal content. Confirm your authority covers the *content* of communications and productivity data, not just device metadata — in many jurisdictions email content carries a higher warrant bar than transactional records. Minimize: query for the scope you are authorized to examine, log every query, and work on copies.

### The iCloud-vs-local provenance axis

Every row in all four stores carries an **account** association, and getting it right is load-bearing. A note "On My iPhone" (local account) behaves completely differently from an iCloud note: the local one never left the device and has no CloudKit server-side copy to subpoena; the iCloud one is replicated, may have **server-side deleted-record tombstones** recoverable via [[06-icloud-acquisition-and-advanced-data-protection]], and is subject to **ADP** (Advanced Data Protection) — which, if enabled, makes the iCloud copy end-to-end encrypted and **breaks cloud acquisition** entirely, leaving the on-device copy as your only avenue.

- **Notes** — accounts live in `ZICCLOUDSYNCINGOBJECT` rows of entity type *ICAccount* (`ZACCOUNTTYPE`, `ZNAME`); a note's account is reached via the note → folder → account chain. A "Local"/"On My iPhone" account is distinguishable from an iCloud (CloudKit) account.
- **Mail** — each configured account (iCloud, Gmail/IMAP, Exchange) is its own mailbox subtree under `Library/Mail/`, and the `Envelope Index` `mailboxes` table maps numeric mailbox IDs to URLs that name the account and folder.
- **Calendar** / **Reminders** — the `Store` table (Calendar) and the account/store entity (Reminders) tag each calendar/list with its source: Local, CalDAV (iCloud), Exchange (EAS), or a subscribed read-only calendar.

> 🔬 **Forensics note:** Provenance answers the "can I still get it from the cloud?" question and the "did this ever leave the device?" question in one shot. A *local-only* note that incriminates is uniquely valuable: it proves the data existed on **this** device and was never synced, foreclosing a "someone else's iCloud pushed it to me" defense.

---

### Notes — `NoteStore.sqlite`

#### The Core Data shape

`NoteStore.sqlite` is a Core Data store, so its tables are **abstract entity tables**, not one-table-per-thing. The big one is `ZICCLOUDSYNCINGOBJECT`: a single physical table that multiplexes *every* object type — notes, folders, accounts, attachments, media — distinguished by the `Z_ENT` column. The companion `Z_PRIMARYKEY` table maps each `Z_ENT` integer to its entity name (`ICNote`, `ICFolder`, `ICAccount`, `ICAttachment`, `ICMedia`, …). You **must** read `Z_PRIMARYKEY` first; the `Z_ENT` integers are not stable across iOS versions.

```
NoteStore.sqlite
├── Z_PRIMARYKEY          ← maps Z_ENT integer → entity name (read this FIRST)
├── Z_METADATA            ← Core Data store metadata / UUID
├── ZICCLOUDSYNCINGOBJECT ← notes, folders, accounts, attachments, media (by Z_ENT)
│     ├─ ICNote rows  ── ZNOTEDATA ──┐
│     ├─ ICFolder rows               │
│     ├─ ICAccount rows              │
│     └─ ICAttachment / ICMedia rows │
└── ZICNOTEDATA  ←───────────────────┘
      └─ ZDATA: GZIP'd protobuf of the note body
```

A note (an *ICNote* row in `ZICCLOUDSYNCINGOBJECT`) holds the **metadata** — title, snippet, folder, account, timestamps, flags — and points via `ZNOTEDATA` to a row in the separate `ZICNOTEDATA` table whose `ZDATA` blob is the **actual body**. The full reconstruction is a chain of self-joins on the one abstract table plus the body table:

```
 ICAccount row        ICFolder row          ICNote row              ZICNOTEDATA row
 (Z_ENT=account)      (Z_ENT=folder)        (Z_ENT=note)            (the body)
 ┌───────────┐  ◀──┐  ┌───────────┐  ◀──┐   ┌───────────┐  ──────▶  ┌──────────┐
 │ ZNAME     │     └──│ ZACCOUNT  │     └───│ ZFOLDER   │   ZNOTEDATA│ ZDATA    │ gzip→protobuf
 │ ZACCOUNT… │        │ ZTITLE2   │         │ ZTITLE1   │            │ ZPLAIN…  │ (parser-added)
 └───────────┘        │ (folder   │         │ ZSNIPPET  │            └────┬─────┘
 iCloud vs local      │  name, inc.│         │ Z*DATE1   │                 │ U+FFFC ￼
                      │  "Recently │         │ ZMARKED…  │                 ▼
                      │  Deleted") │         └───────────┘            ICAttachment / ICMedia
                      └───────────┘                                   (+ Media/ files on disk)
```

The forensically load-bearing columns on the *ICNote* rows:

| Column | Meaning / gotcha |
|---|---|
| `ZTITLE` / `ZTITLE1` | Note title (the first line). Suffix varies by version — inspect the schema. |
| `ZSNIPPET` | Preview text (first ~N chars). A quick triage field that *survives* even when you haven't decompressed the body. |
| `ZCREATIONDATE1` | Created — **Mac-Absolute Time** (seconds since 2001-01-01 UTC). |
| `ZMODIFICATIONDATE1` / `ZMODIFIEDDATE1` | Last modified — Mac-Absolute. Column suffix varies by iOS version; confirm against the live schema. |
| `ZMARKEDFORDELETION` | `1` = tombstoned, pending CloudKit purge. Soft-delete flag (see below). |
| `ZISPASSWORDPROTECTED` | `1` = locked note; the gzipped body is **encrypted *after* compression** (AES-GCM), so `ZDATA` is raw ciphertext with no `1f 8b` header — a plain `gunzip` errors out; decrypt first (see ⚠️ below). |
| `ZACCOUNT` / `ZACCOUNT2` … | Foreign key toward the owning *ICAccount* row → iCloud vs local provenance. |
| `ZFOLDER` | Foreign key toward the owning *ICFolder* row → including the special "Recently Deleted" folder. |
| `ZIDENTIFIER` | CloudKit UUID — stable cross-device identity; the join key to server-side records. |

> 🔬 **Forensics note:** `ZSNIPPET` is the field button-pushers forget. Even on a note whose body you cannot (or did not) decompress — and even on some rows whose `ZDATA` has been purged — the snippet column preserves the opening text of the note. Triage every `ICNote` row's `ZSNIPPET` before deciding which bodies are worth decompressing.

#### The body: a GZIP'd protobuf

`ZICNOTEDATA.ZDATA` is **not** text and **not** a plain protobuf. It is a **GZIP stream** (`1f 8b` magic, RFC 1952) wrapping an Apple protobuf (`NoteStoreProto`). The decode pipeline is fixed:

```
ZDATA blob ──(gunzip)──▶ protobuf bytes ──(parse NoteStoreProto)──▶ note text + run-length style attributes
                                                       │
                                          embedded objects are NOT inline:
                                          the body text contains U+FFFC (￼, "object
                                          replacement character") at each insertion
                                          point, resolved via ICAttachment/ICMedia rows
```

The protobuf nesting is roughly `NoteStoreProto → document → note`, where the `note` message has a `note_text` string (the human-readable body) plus parallel arrays of **attribute runs** (bold/heading/checklist/link styling applied to character ranges). For a fast "what does this note say?" you only need `note_text`; for fidelity (which words were a checklist item, which were a hyperlink) you need the attribute runs — which is why you hand the blob to a real parser rather than `strings` for anything you'll testify to.

Embedded content — a photo, a scanned document, a drawing, a table, a hashtag, a mention — appears in `note_text` as the single character **U+FFFC (`￼`)**. Each `￼` is a placeholder; the real object is an *ICAttachment*/*ICMedia* row (with its own `ZTYPEUTI` UTI, e.g. `public.jpeg`, `com.apple.notes.table`) whose media bytes live in the Notes group container's `Media/`/`FallbackImages/` subfolders, keyed by `ZIDENTIFIER`. To reconstruct a note faithfully you walk the `￼` positions and substitute each attachment in order.

#### Deleted notes: soft-delete and the 30-day window

Deletion in Notes is a two-stage soft-delete:

1. **User deletes a note** → it is **reparented** into the special *ICFolder* named "Recently Deleted." The note row and its `ZDATA` are still fully present and readable — only its folder changed.
2. **After ~30 days (or on the next iCloud sync purge)** → the object is tombstoned: `ZMARKEDFORDELETION = 1`, then eventually the row and its `ZICNOTEDATA` body are physically removed.

This produces three recoverable tiers: (a) live notes; (b) notes in "Recently Deleted" — fully intact, just in a different folder; (c) tombstoned/`ZMARKEDFORDELETION = 1` rows whose bodies may already be gone but whose *metadata* (title, dates, account) survives until the row is reaped. Below all three, **deleted SQLite pages in the WAL and in unallocated database space** can yield gzipped `ZDATA` fragments long after the row is gone — `1f 8b` is a clean carving signature.

> 🔬 **Forensics note:** Because the live "deletion" is a reparent, the most overlooked smoking gun is a note sitting in **Recently Deleted with `ZMARKEDFORDELETION = 0`** — a suspect "deleted" it, believes it gone, and it is sitting there in plaintext (post-gunzip) for a month. Always enumerate the Recently Deleted folder's contents explicitly; many vendor "Notes" views fold it into the live list or omit it.

> ⚠️ **ADVANCED — locked (password-protected) notes.** When `ZISPASSWORDPROTECTED = 1`, the layering is **compress-then-encrypt** (the standard, sensible order — you compress plaintext, *then* encrypt the result): the protobuf is gzipped first, and that gzip stream is then **AES-GCM**-encrypted. So `ZDATA` is raw ciphertext with **no `1f 8b` gzip magic** — a naïve `gunzip` doesn't "yield noise," it simply *errors out* because there is no gzip header to read. The decode pipeline reverses the layers: **decrypt → gunzip → parse protobuf**. The key schedule is two-stage: PBKDF2-SHA256 over the user's note password derives a key-encrypting key, which RFC 3394 **AES-Key-Wrap**-unwraps the actual 16-byte content key, which finally AES-GCM-decrypts the blob. The crypto parameters sit as columns on the *ICNote* row in `ZICCLOUDSYNCINGOBJECT`: `ZCRYPTOSALT`, `ZCRYPTOITERATIONCOUNT`, `ZCRYPTOWRAPPEDKEY`, `ZCRYPTOINITIALIZATIONVECTOR`, and the GCM auth tag `ZCRYPTOTAG` (exact column names/placement drift by iOS version — `.schema` the table). Recovery is an **offline password-cracking** problem: extract salt, iterations, IV, tag, wrapped key, and ciphertext into a hashcat-compatible format and attack the user's note password (often the device passcode or a reused password). This is the only one of the four stores with per-item user encryption layered *on top of* Data Protection; do not mistake the ciphertext for corruption.

---

### Mail — `Envelope Index` + `Protected Index` + `.emlx`

iOS Mail does **not** keep everything in one database. It splits across three things under `/private/var/mobile/Library/Mail/`:

```
/private/var/mobile/Library/Mail/
├── Envelope Index            ← SQLite: dates, message/thread IDs, mailbox map  (+ -wal/-shm)
├── Protected Index           ← SQLite: senders/recipients, subjects, summaries (+ -wal/-shm)
├── <AccountUUID>/            ← per-account mailbox tree (IMAP/iCloud/Exchange)
│     ├─ INBOX.mbox/ …/Messages/*.emlx
│     ├─ Sent Messages.mbox/ …
│     ├─ Trash.mbox/ …        ← "deleted" mail lands here first
│     └─ .mboxCache.plist     ← maps numeric folder IDs → human folder names
└── MessageData/              ← individual .emlx message files (content + headers)
```

**`Envelope Index`** is the high-level metadata catalogue: a `messages` table (message IDs, conversation/thread IDs, flags, the **date fields**, and a foreign key to a mailbox) and a `mailboxes` table whose `url` column names the account+folder. Crucially, the Envelope Index date fields (`date_received`, `date_sent`, `date_created`, `date_last_viewed`) are stored as **Unix epoch seconds** — *not* Mac-Absolute. This is the exception to the "everything Apple is 2001-epoch" rule; convert with `datetime(date_received,'unixepoch','localtime')` and **no** `+978307200`.

**`Protected Index`** holds the substantive content fields, separated out (the name reflects its higher Data-Protection class). Across iOS versions the table layout shifted:

| iOS era | Protected Index tables | Holds |
|---|---|---|
| iOS 12 | `messages`, `message_data` | sender/subject/to/cc/bcc; first ~500 bytes of body |
| iOS 13+ | `Addresses`, `Subjects`, `Summaries`, `protected_message_data` | email addresses + display names; subjects; first ~500-byte content summaries; (full body table often empty) |

So a "who emailed whom about what" answer is a **join across two databases**: the `Envelope Index` gives you dates, thread, and mailbox; the `Protected Index` gives you the addresses, subject, and the summary snippet. The `Summaries` table's ~500-byte preview is frequently *enough* — and it is present even when the full `.emlx` has been pruned.

**`.emlx` files** are the full messages: standard RFC 822/MIME (headers + body, frequently `quoted-printable`- or Base64-encoded), wrapped in Apple's `.emlx` envelope (a leading byte-count line, the MIME message, and a trailing binary-plist of Mail's per-message flags). Attachments are inside the MIME or alongside. Partial downloads can leave **fragmentary `.emlx`** that need reassembly.

> 🔬 **Forensics note:** "Deleted" mail is a goldmine because of where it goes. Deleting in Mail.app **moves the message to the account's `Trash.mbox`** — the `.emlx` is still there, and the `Envelope Index`/`Protected Index` rows still resolve, until the trash is emptied (and IMAP/Exchange `EXPUNGE` propagates). Even after emptying, the Envelope/Protected indexes are lazily pruned and orphaned `.emlx` files linger; the WAL of both indexes carries deleted rows. Check `Trash.mbox`, then the index WALs, before reporting "no deleted mail."

> 🔬 **Forensics note:** The `.mboxCache.plist` is the Rosetta stone for the numeric mailbox/folder IDs the indexes use — it maps them to names ("Drafts", "Sent", "Trash", custom folders). Without it, a `mailbox = 8` row is meaningless; with it, you can say "this was in Drafts," which distinguishes a *composed-but-never-sent* message (intent) from a sent one.

---

### Calendar — `Calendar.sqlitedb`

`Calendar.sqlitedb` is EventKit's backing store, and unlike Notes/Reminders it is a **hand-rolled relational schema** (not Core Data — no `Z`-prefixed abstract entity tables), which makes it the most pleasant of the four to query directly. The core tables:

| Table | Role | Key columns (verify exact names on your image) |
|---|---|---|
| `Store` | Account/source per calendar | `name`, `type` (Local / CalDAV-iCloud / Exchange / Subscribed) |
| `Calendar` | A calendar (Home, Work, a shared cal) | `title`, `color`, `store_id`, `flags` |
| `CalendarItem` | **One row per event** | `summary` (title), `start_date`, `end_date`, `all_day`, `calendar_id`, `location_id`, `organizer_id`, `last_modified`, `description`/`notes`, `unique_identifier`, `external_id` |
| `Location` | Place attached to an event | `title` (place name), and structured address / lat-long fields |
| `Identity` | A person (organizer or attendee) | `display_name`, `address` (email) |
| `Participant` | Links `CalendarItem` ↔ `Identity` | `owner_id` (event), `identity_id`, `status`, `role` |
| `Alarm` | Event alerts/reminders | trigger offset / absolute time, `calendaritem_owner_id` |
| `Recurrence` | Repeat rules | RRULE frequency/interval/until, `owner_id` |

`CalendarItem.start_date` / `end_date` are **Mac-Absolute Time** (seconds since 2001), stored **in UTC** with a separate timezone reference — which is the standard Calendar trap: a tool that ignores the event's stored timezone (or treats a *floating* all-day event as UTC) shifts wall-clock times by hours. All-day and "floating" events deliberately carry no fixed UTC instant; render them by date, not by converting an instant.

> 🔬 **Forensics note:** Calendar is the only one of the four that records **deliberate future intent with place + people**. An event is not passive telemetry like a location fix — the user *typed it in*. Join `CalendarItem → Location` (where they planned to be), `CalendarItem → Participant → Identity` (who they planned to be with), and `last_modified` (when they last touched the plan), and you have a defensible statement that the subject intended to be at a named place, with named people, at a specific time. The `description`/notes field on an event frequently carries dial-in numbers, addresses, or free-text plans. Compare planned events against [[07-location-history]] fixes to confirm or refute that the plan was executed.

> 🔬 **Forensics note:** Deleted events are not always gone. Recurring-event *exceptions* (a single deleted occurrence of a repeating event) leave detached/cancelled rows; declined invitations persist as `Participant` rows with a declined `status`; and the WAL holds recently deleted `CalendarItem` rows. The `last_modified` column lets you spot events that were edited after the fact.

---

### Reminders — `Data-<UUID>.sqlite`

Reminders was re-architected in **iOS 13** onto a new EventKit-backed Core Data store. The current data lives under `Library/Reminders/Container_v1/Stores/Data-<UUID>.sqlite` (and a parallel `group.com.apple.reminders/Container_v1/Stores/` group container); older devices/upgrades may still carry a **legacy `Reminders.sqlitedb`** with pre-iOS-13 data — check both.

Being Core Data, it has the same abstract-entity shape as Notes: the workhorse table is `ZREMCDOBJECT` (mapped from the `REMCDObject` entity), multiplexing **both reminders and lists** by `Z_ENT`, with `Z_PRIMARYKEY` giving the entity-name mapping. The forensically useful columns on a reminder row:

| Column (verify suffix on your image) | Meaning |
|---|---|
| `ZTITLE` / `ZTITLE1` | The reminder text. |
| `ZNOTES` | Free-text notes attached to the reminder. |
| `ZCREATIONDATE` | Created — Mac-Absolute Time. |
| `ZLASTMODIFIEDDATE` | Last edited — Mac-Absolute. |
| `ZDUEDATE` / `ZDUEDATECOMPONENTS` | When it's due (time-based trigger). |
| `ZCOMPLETED` / `ZCOMPLETIONDATE` | Whether/when it was checked off — a behavioral timestamp ("they marked this done at 02:14"). |
| `ZFLAGGED`, `ZPRIORITY` | Flag/priority. |
| `ZLIST` / parent FK | The owning list (itself a `ZREMCDOBJECT` row of the list entity → account/store → iCloud vs local). |
| location-trigger fields | A geofenced "remind me here" stores a **named place and coordinates** + arriving/leaving trigger. |

> 🔬 **Forensics note:** The location-trigger on a reminder is an under-appreciated **address artifact**. "Remind me to call the lawyer when I get to 442 Oak St" stores that street address and its lat/long as a geofence, independent of any Location Services history — it can place an address in the subject's world even if Significant Locations is empty or disabled. And `ZCOMPLETIONDATE` is a genuine pattern-of-life timestamp: it marks a moment the user was actively interacting with the device to tick a box.

#### Reading any Core Data store (the universal move)

Both Notes and Reminders are Core Data, so the same demux applies. `Z_PRIMARYKEY` tells you which `Z_ENT` integer is which entity, and `Z_METADATA` carries the store UUID and version. Always start there:

```sql
-- What entities exist and what Z_ENT integer is each?
SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY ORDER BY Z_ENT;
-- Then filter the abstract table to just reminders (substitute the integer you found):
-- SELECT ZTITLE1, ZDUEDATE, ZCOMPLETIONDATE FROM ZREMCDOBJECT WHERE Z_ENT = <reminder-ent>;
```

---

### The timestamp zoo for these four stores

| Store | Field(s) | Epoch | Conversion |
|---|---|---|---|
| Notes | `ZCREATIONDATE1`, `ZMODIFICATIONDATE1` | Mac-Absolute (2001), **seconds** | `+978307200`, then `unixepoch` |
| Calendar | `CalendarItem.start_date`/`end_date`, `last_modified` | Mac-Absolute (2001), **seconds**, stored UTC | `+978307200`; apply the event's timezone |
| Reminders | `ZCREATIONDATE`, `ZDUEDATE`, `ZCOMPLETIONDATE` | Mac-Absolute (2001), **seconds** | `+978307200`, then `unixepoch` |
| **Mail (Envelope Index)** | `date_received`, `date_sent`, `date_created` | **Unix (1970), seconds** | `unixepoch` directly — **no** `+978307200` |

Mail is the odd one out. Mixing Mail's Unix-epoch dates with the Mac-Absolute math you use everywhere else lands you ~31 years off — the same "30-year trap" from [[04-communications-imessage-and-sms]], in reverse. See [[00-the-ios-timestamp-zoo]].

## Hands-on

There is no on-device shell — everything runs Mac-side against a copy of the stores (pulled from an acquisition, a sample image, or a Simulator container). **Copy-before-query is mandatory:** even a `SELECT` write-locks SQLite and a client open can checkpoint the WAL, destroying recoverable deleted rows.

### Stage the evidence safely

```bash
# Copy the database AND its sidecars as one set, then hash.
for f in NoteStore.sqlite NoteStore.sqlite-wal NoteStore.sqlite-shm; do
  cp -p "/path/to/evidence/$f" "/tmp/notes/$f" 2>/dev/null
done
shasum -a 256 /tmp/notes/*           # record in your notes
sqlite3 /tmp/notes/NoteStore.sqlite "PRAGMA journal_mode;"   # expect: wal
```

### Notes: enumerate, then decompress a body by hand

```bash
DB=/tmp/notes/NoteStore.sqlite

# 1) Demux the Core Data entities (find the ICNote Z_ENT integer)
sqlite3 "$DB" "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY ORDER BY Z_ENT;"

# 2) Triage: titles, snippets, dates, delete-state, account — no decompression yet
sqlite3 -header -column "$DB" "
SELECT obj.Z_PK,
       obj.ZTITLE1                                         AS title,
       obj.ZSNIPPET                                        AS snippet,
       datetime(obj.ZCREATIONDATE1     + 978307200,'unixepoch','localtime') AS created,
       datetime(obj.ZMODIFICATIONDATE1 + 978307200,'unixepoch','localtime') AS modified,
       obj.ZMARKEDFORDELETION          AS tombstoned,
       obj.ZISPASSWORDPROTECTED        AS locked
FROM ZICCLOUDSYNCINGOBJECT obj
WHERE obj.ZNOTEDATA IS NOT NULL
ORDER BY obj.ZMODIFICATIONDATE1 DESC;"

# 3) Pull ONE note's gzipped body out to a file using SQLite's writefile()
#    (substitute the ZNOTEDATA target Z_PK from the row you care about)
sqlite3 "$DB" "SELECT writefile('/tmp/notes/note.gz', ZDATA)
               FROM ZICNOTEDATA WHERE Z_PK = 12;"

# 4) Decompress (it's real gzip: 1f 8b magic) and read the protobuf
file /tmp/notes/note.gz                       # → gzip compressed data
gunzip -c /tmp/notes/note.gz > /tmp/notes/note.pb
protoc --decode_raw < /tmp/notes/note.pb | less   # structured field dump
strings -n 4 /tmp/notes/note.pb                   # quick-and-dirty body peek
```

`protoc --decode_raw` shows the protobuf field tree without a `.proto` schema; the long string field inside `document → note` is `note_text`. For production-grade output (attributes, embedded objects, locked-note handling) use the dedicated parser below.

### Notes: the dedicated parsers

```bash
# threeplanetssoftware/apple_cloud_notes_parser (Ruby) — the reference Notes parser.
# Decompresses every ZDATA, parses the protobuf, resolves embedded objects, and
# writes back a ZPLAINTEXTDATA column + CSV/HTML reports.
ruby notes_cloud_ripper.rb -f /tmp/notes/NoteStore.sqlite

# mac_apt's iOS front-end (ios_apt.py) runs the same NOTES plugin over an iOS FFS extraction.
# -i = extraction root folder, -o = output dir, trailing positional = plugin(s); SQLite is the default output.
python3 ios_apt.py -i /path/to/extracted_fs -o /tmp/out NOTES

# iLEAPP parses Notes among ~hundreds of iOS artifacts from a logical/FFS extraction
python3 ileapp.py -t fs -i /path/to/extracted_fs -o /tmp/ileapp_out
```

### Mail: join the two indexes; read an `.emlx`

```bash
# Envelope Index date fields are UNIX epoch — note: NO 978307200 offset.
sqlite3 -header -column "/tmp/mail/Envelope Index" "
SELECT m.ROWID,
       datetime(m.date_received,'unixepoch','localtime') AS received,
       mb.url                                             AS mailbox
FROM messages m
LEFT JOIN mailboxes mb ON m.mailbox = mb.ROWID
ORDER BY m.date_received DESC LIMIT 40;"

# Protected Index (iOS 13+): subjects + summaries (the ~500-byte preview)
sqlite3 -header -column "/tmp/mail/Protected Index" "
SELECT s.subject, sum.summary
FROM Subjects s LEFT JOIN Summaries sum ON s.message_id = sum.message_id
LIMIT 40;"

# Read a raw message: .emlx = byte-count line + MIME + trailing plist.
# Skip the first line (the length), hand the rest to a MIME-aware reader.
sed '1d' "/tmp/mail/MessageData/123.emlx" | less
```

### Calendar: events with place and people

```bash
sqlite3 -header -column /tmp/cal/Calendar.sqlitedb "
SELECT ci.summary                                              AS event,
       datetime(ci.start_date + 978307200,'unixepoch','localtime') AS start,
       datetime(ci.end_date   + 978307200,'unixepoch','localtime') AS end_,
       loc.title                                               AS place,
       cal.title                                               AS calendar,
       st.name                                                 AS account
FROM CalendarItem ci
LEFT JOIN Location loc ON ci.location_id = loc.ROWID
LEFT JOIN Calendar cal ON ci.calendar_id = cal.ROWID
LEFT JOIN Store    st  ON cal.store_id   = st.ROWID
ORDER BY ci.start_date DESC LIMIT 40;"

# Attendees for a given event (owner_id = the CalendarItem ROWID)
sqlite3 -header -column /tmp/cal/Calendar.sqlitedb "
SELECT id.display_name, id.address, p.status, p.role
FROM Participant p JOIN Identity id ON p.identity_id = id.ROWID
WHERE p.owner_id = 17;"
```

### Reminders: demux Core Data, list open + completed

```bash
DB=/tmp/rem/Data-XXXX.sqlite
sqlite3 "$DB" "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY ORDER BY Z_ENT;"   # find reminder Z_ENT
sqlite3 -header -column "$DB" "
SELECT ZTITLE1 AS reminder,
       datetime(ZCREATIONDATE   + 978307200,'unixepoch','localtime') AS created,
       datetime(ZDUEDATE        + 978307200,'unixepoch','localtime') AS due,
       datetime(ZCOMPLETIONDATE + 978307200,'unixepoch','localtime') AS completed,
       ZFLAGGED
FROM ZREMCDOBJECT
WHERE ZTITLE1 IS NOT NULL
ORDER BY ZCREATIONDATE DESC;"
```

## 🧪 Labs

> The Simulator gives you the **real schemas** with zero device. Fidelity caveat for every Simulator lab: CoreSimulator runs on macOS frameworks, so there is **no Data-Protection encryption, no SEP, and no BFU/AFU lock-state behavior** — the stores sit unencrypted on disk and `notesd`/`remindd`/CloudKit sync is not exercised the way a device does it. The Simulator faithfully teaches *structure, schema, and the decompress/decode pipeline*; it does **not** teach the at-rest encryption or the cloud-tombstone behavior — those come from sample images. **Mail.app is not bundled in the iOS Simulator**, so the Mail lab uses a public reference image.

### Lab 1 — Notes schema + decompress a body (Simulator)

1. Boot a Simulator and open Notes: `xcrun simctl boot "iPhone 17 Pro"` then `xcrun simctl launch booted com.apple.mobilenotes` (or open it in the Simulator UI). Type a note with a heading, a checklist, and an inserted photo. Add a second note, then **delete** it (it goes to Recently Deleted).
2. Locate the store under the device's data root:
   `find ~/Library/Developer/CoreSimulator/Devices -name NoteStore.sqlite 2>/dev/null`
3. Copy the triplet (`.sqlite`, `-wal`, `-shm`) to `/tmp/notes/`, hash them, confirm `PRAGMA journal_mode` is `wal`.
4. Run the Step-1 `Z_PRIMARYKEY` query, then the Step-2 triage query. Identify your two notes; confirm the deleted one is present (in the Recently Deleted folder, `ZMARKEDFORDELETION` likely still `0`).
5. `writefile()` the first note's `ZDATA` out, `gunzip` it, and run `protoc --decode_raw`. Find your body text in the `note_text` field. Find the **U+FFFC** placeholder where you inserted the photo, and locate the matching attachment row.

### Lab 2 — Calendar events with place + attendees (Simulator)

1. In the Simulator's Calendar app, create an event with a **title, a location (place name), a start/end time, and an alert**. Create a second, all-day event.
2. `find ~/Library/Developer/CoreSimulator/Devices -name Calendar.sqlitedb 2>/dev/null`; copy it (+ sidecars).
3. Run the Calendar Hands-on join. Confirm `start_date` converts correctly with `+978307200`. Verify the all-day event's behavior (it should render by date; note how its stored instant differs).
4. `.schema CalendarItem` and `.schema Location` — confirm the exact column names against what this lesson lists, and note any that differ on your OS version. Inspect the `Store` table to see the Simulator's local account.

### Lab 3 — Reminders as raw Core Data (Simulator)

1. In the Simulator's Reminders app, add three reminders: one with a **due date/time**, one **flagged**, and one you then **mark complete**.
2. `find ~/Library/Developer/CoreSimulator/Devices -path '*Reminders*' -name 'Data-*.sqlite' 2>/dev/null`; copy it.
3. Run `SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY` and identify which integer is the reminder entity vs the list entity. Then run the Reminders Hands-on query.
4. Confirm `ZCOMPLETIONDATE` is populated only for the completed reminder, and that converting it gives the moment you tapped the checkbox. (Geofence/location-trigger fields won't populate meaningfully on the Simulator — note this as a fidelity gap.)

### Lab 4 — Mail Protected Index + `.emlx` (public sample image)

> Mail is device-only, so use a public reference image: Josh Hickman's iOS reference images (thebinaryhick.blog / Digital Corpora) or the iLEAPP test data, mounted/extracted read-only.

1. From the extraction, locate `Library/Mail/`. Copy `Envelope Index` and `Protected Index` (with their `-wal`/`-shm`) and the `MessageData/` + an account `*.mbox/` subtree.
2. Run the Envelope Index query — verify the dates are **Unix epoch** (a 2021-ish image should render as 2021 with `unixepoch` and **no** offset; if you wrongly add `978307200` you'll see ~2052).
3. Join `Subjects` ↔ `Summaries` in the Protected Index for the "who/what" without ever opening an `.emlx`. Note how the ~500-byte summary alone answers many questions.
4. Open one `.emlx` (skip the first byte-count line), and decode any `quoted-printable`/Base64 body. Then look in the account's `Trash.mbox/` for a deleted message that still has a live `.emlx`.

### Lab 5 — Deleted-data reasoning across the WAL (Simulator + carving)

1. On the Lab-1 Notes store, after deleting a note, **before** opening it in a checkpointing client, run `strings` over `NoteStore.sqlite-wal` and search for `1f 8b` gzip headers (`xxd NoteStore.sqlite-wal | grep -i '1f8b'`).
2. Reflect on the handling rule: had you copied only the `.sqlite` and opened it, the client would have checkpointed and you might have lost the uncheckpointed frames. Document why the triplet is one evidence set.
3. (Stretch) Use a SQLite recovery/carving tool (e.g., `sqlite3 .recover`, or a forensic carver) against a copy to surface rows not visible in a normal `SELECT`.

## Pitfalls & gotchas

- **The Notes body is gzip, not protobuf-first.** A naive "parse `ZDATA` as protobuf" fails on the `1f 8b` header — you must `gunzip` *first*. And `strings` on the decompressed blob is a triage shortcut, not a faithful render: it drops the attribute runs and silently omits embedded objects (the `￼` placeholders).
- **Mail's epoch is Unix, everything else is Mac-Absolute.** Applying `+978307200` to `Envelope Index` dates throws Mail timestamps ~31 years into the future. Applying *no* offset to Notes/Calendar/Reminders throws those ~31 years into the past. Match the epoch to the store.
- **Core Data table names are abstract.** `ZICCLOUDSYNCINGOBJECT` and `ZREMCDOBJECT` each hold *multiple* entity types. Querying them without filtering by the correct `Z_ENT` (resolved through `Z_PRIMARYKEY`) mixes notes with folders, reminders with lists. The `Z_ENT` integers are **not stable across iOS versions** — re-derive them per image.
- **Column-name suffixes drift by version.** `ZCREATIONDATE1` vs `ZCREATIONDATE2`, `ZTITLE` vs `ZTITLE1`, `ZMODIFICATIONDATE1` vs `ZMODIFIEDDATE1` — Core Data renumbers columns as the model evolves. Always `.schema` the table on the actual image; do not hardcode a suffix from another case.
- **"Deleted" rarely means gone.** Notes reparent to Recently Deleted (intact for ~30 days); Mail moves to `Trash.mbox` (the `.emlx` persists); Calendar leaves cancelled/exception rows; all four carry deleted rows in the WAL. Reporting "no deleted data" after only reading live rows is an examiner error, not a fact about the device.
- **Locked notes look like corruption.** `ZISPASSWORDPROTECTED = 1` means `ZDATA` is **compress-then-encrypt**: the gzipped protobuf is AES-GCM-encrypted, so the blob is ciphertext with no `1f 8b` header and a plain `gunzip` *errors out* (it does not silently emit noise). That is not a bad copy — the pipeline is `decrypt → gunzip → protobuf`, and absent the password it's an offline password-cracking problem (extract salt/iterations/IV/tag/wrapped-key, attack with hashcat).
- **iCloud + ADP changes the playing field.** If Advanced Data Protection is on, the iCloud copies of Notes/Mail-via-iCloud/Calendar/Reminders are E2EE and cloud acquisition is dead — the on-device copy is everything. Conversely, *without* ADP, server-side **tombstones** may recover items already purged from the device.
- **The Simulator has no encryption and no device daemons.** It is perfect for schema and the decode pipeline, useless for at-rest-encryption realism, geofence population, and cloud-sync/tombstone behavior. Caveat every Simulator finding accordingly and corroborate device-only behavior from sample images.
- **Calendar timezone handling.** `start_date`/`end_date` are UTC Mac-Absolute with a *separate* timezone reference; floating and all-day events have no fixed instant. A naive `localtime` conversion that ignores the event's timezone will misplace events by hours and mis-render all-day events.

## Key takeaways

- The productivity quartet (Notes, Mail, Calendar, Reminders) is where the decisive free-text/intent evidence usually lives; all four are AFU-readable SQLite that is opaque in BFU.
- **Notes** keeps the body as a **GZIP'd protobuf** in `ZICNOTEDATA.ZDATA` — `gunzip` then parse; `￼` (U+FFFC) marks embedded objects resolved via attachment rows; `ZSNIPPET` triages without decompression.
- **Mail** splits across `Envelope Index` (dates/mailboxes, **Unix epoch**) + `Protected Index` (addresses/subjects/summaries) + per-message `.emlx`; deletes land in `Trash.mbox` and the index WALs.
- **Calendar** (`Calendar.sqlitedb`) is a clean relational schema recording **deliberate intent + place + attendees**; join `CalendarItem → Location → Participant → Identity`, mind the UTC/timezone/floating-event trap.
- **Reminders** is Core Data (`ZREMCDOBJECT`, demux via `Z_PRIMARYKEY`); `ZCOMPLETIONDATE` is a real pattern-of-life timestamp and location-trigger fields are an under-used **address** artifact.
- Everything is Mac-Absolute (2001) **except Mail's Envelope Index** (Unix 1970) — match the epoch to the store or land ~31 years off.
- Track **iCloud-vs-local provenance** on every row: it decides cloud-recoverability, ADP exposure, and the "did this ever leave the device?" question.
- "Deleted" is recoverable in all four (Recently Deleted, Trash, cancelled rows, WAL/unallocated) — never report "no deleted data" from live rows alone.

## Terms introduced

| Term | Definition |
|---|---|
| `NoteStore.sqlite` | Apple Notes' Core Data SQLite store; note body lives as a GZIP'd protobuf in `ZICNOTEDATA.ZDATA`. |
| `ZICCLOUDSYNCINGOBJECT` | Core Data abstract table multiplexing Notes' notes/folders/accounts/attachments, distinguished by `Z_ENT`. |
| `ZICNOTEDATA` | Notes table whose `ZDATA` blob holds the per-note GZIP'd protobuf body. |
| `Z_PRIMARYKEY` | Core Data metadata table mapping each `Z_ENT` integer to its entity name; read it before querying any abstract table. |
| `ZMARKEDFORDELETION` | Notes soft-delete/tombstone flag (`1` = pending CloudKit purge). |
| `NoteStoreProto` | The protobuf message family describing a note's text + attribute runs after gunzip. |
| U+FFFC (`￼`) | Object Replacement Character — placeholder in note text marking an embedded object resolved via attachment rows. |
| `Envelope Index` | iOS Mail SQLite catalogue of message dates/IDs/mailboxes; date fields are **Unix epoch**. |
| `Protected Index` | iOS Mail SQLite holding senders/recipients (`Addresses`), `Subjects`, and ~500-byte `Summaries`. |
| `.emlx` | Apple Mail per-message file: byte-count line + RFC 822/MIME message + trailing flags plist. |
| `.mboxCache.plist` | Maps iOS Mail's numeric mailbox/folder IDs to human folder names. |
| `Calendar.sqlitedb` | EventKit's relational backing store: `Store`/`Calendar`/`CalendarItem`/`Location`/`Identity`/`Participant`/`Alarm`/`Recurrence`. |
| `CalendarItem` | One-row-per-event Calendar table (summary, start/end Mac-Absolute UTC, location/organizer FKs). |
| `ZREMCDOBJECT` | Core Data abstract table backing Reminders (reminders + lists), in `Library/Reminders/Container_v1/Stores/`. |
| Mac-Absolute Time | Apple timestamp epoch: seconds since 2001-01-01 UTC; convert with `+978307200`. |

## Further reading

- Apple Platform Security guide — Data Protection classes (Notes/Mail/Calendar/Reminders are typically Class C, `…CompleteUntilFirstUserAuthentication`).
- threeplanetssoftware/`apple_cloud_notes_parser` (Ciofeca Forensics / "Revisiting Apple Notes" blog series) — the reference Notes protobuf + CloudKit parser; read the README and the `.proto` definitions.
- Ciofeca Forensics, "Revisiting Apple Notes" (parts 1, 2, 5, 7) — embedded objects, encrypted notes, CloudKit data.
- Yogesh Khatri (swiftforensics.com) — "Reading Notes database," "iOS Application Groups & Shared data"; `mac_apt` `NOTES` plugin.
- Ian Whiffin (doubleblak.com/iosmail) — definitive iOS Mail `Envelope Index` / `Protected Index` / `.emlx` walkthrough and version differences.
- Alexis Brignoni — iLEAPP (Notes/Mail/Calendar/Reminders parsers + test data).
- Sarah Edwards (mac4n6.com) — "An Initial Look into Protobuf Data in Mac and iOS Forensics."
- forensafe.com "iOS Calendar"; "Practical Mobile Forensics" (Calendar/Reminders chapters) — `Calendar.sqlitedb` and Reminders schema.
- `man sqlite3` (`.schema`, `.recover`, `writefile`), `man protoc` / `protoc --decode_raw`, `man gunzip`.

---
*Related lessons: [[00-app-sandbox-and-filesystem-layout]] | [[04-communications-imessage-and-sms]] | [[07-location-history]] | [[00-the-ios-timestamp-zoo]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[14-deleted-data-recovery]]*
