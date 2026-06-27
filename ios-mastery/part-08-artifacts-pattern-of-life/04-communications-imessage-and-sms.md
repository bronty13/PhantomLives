---
title: "Communications: iMessage & SMS"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 04
est_time: "50 min read + 25 min labs"
prerequisites: [app-sandbox-and-filesystem-layout]
tags: [ios, forensics, imessage, sms, chat-db, sqlite, dfir]
last_reviewed: 2026-06-26
---

# Communications: iMessage & SMS

> **In one sentence:** Every text-based conversation on an iPhone — iMessage, SMS, RCS, attachments, read receipts, edits, and 30-day "Recently Deleted" remnants — lives in one unencrypted-once-acquired SQLite store, `sms.db`, whose relational schema, nanosecond Mac-Absolute timestamps, and `typedstream`-archived message bodies you must be able to reconstruct by hand before you trust any tool's "conversation view."

## Why this matters

`sms.db` is usually the single highest-yield communications artifact on an iOS device, and it is the one investigators most often misread. Three traps do the damage: the message body is frequently **`NULL` in the obvious `text` column** (it's hidden in a serialized `attributedBody` blob), the timestamps are in a **nanosecond** flavour of Mac-Absolute time that silently throws results decades off if you forget a divide, and "deleted" messages are routinely still **right there** — in the WAL, in unallocated pages, or in the iOS 16+ Recently-Deleted join table — invisible to anyone who only `SELECT`s the live rows a vendor tool shows them. A forensicator who can write the joins, fix the epoch, decode the `typedstream`, and carve the WAL recovers conversations that a button-pushing examiner reports as "no data." This lesson is the schema, the format internals, and the recovery mechanics — at the level where you can defend every cell in court.

## Concepts

### The store and its sidecars

```
/private/var/mobile/Library/SMS/
├── sms.db                 ← the SQLite database (WAL journal mode)
├── sms.db-wal             ← write-ahead log: uncheckpointed (incl. DELETED) rows live here
├── sms.db-shm             ← shared-memory index for the WAL
├── Attachments/           ← path-sharded media tree (see below)
├── StickerCache/
└── Drafts/                ← per-thread unsent drafts (composing.plist)
```

`sms.db` is a normal SQLite 3 database running in **WAL (write-ahead logging) mode** — `PRAGMA journal_mode` returns `wal`. That single fact dictates your handling discipline: the live database file is *not* the whole truth. Recently written and recently deleted rows sit in `sms.db-wal` until a checkpoint folds them back into the main file, and **opening the database with a normal SQLite client triggers an automatic checkpoint that can destroy recoverable deleted rows.** Treat `sms.db`, `sms.db-wal`, and `sms.db-shm` as one inseparable evidence set — copy all three together, hash all three, and never let a tool open the original.

> 🔬 **Forensics note:** Copy-before-query is not optional and it is not enough to copy `sms.db` alone. If you copy only `sms.db` and then open it, SQLite sees the `-wal` is gone and you have silently discarded every uncheckpointed frame — including deleted messages that were never folded into the main file. Acquire the triplet, then work the `-wal` out-of-band with a carver *before* you ever let a client checkpoint it.

> 🖥️ **macOS contrast:** This is the device-side twin of the `~/Library/Messages/chat.db` you dissected in macOS Mastery — **identical schema, identical nanosecond epoch, identical `attributedBody` blob.** Continuity (Text Message Forwarding + Messages in iCloud) keeps them in sync, so a suspect's Mac is a second, often AFU-accessible copy of the same conversations. When the phone is locked (BFU) and undecryptable, the paired Mac's FileVault-protected-but-often-unlocked `chat.db` may be your fastest path to the same content.

### The relational model

`sms.db` is a textbook many-to-many schema. Messages are not stored inside conversations; they are *joined* to them. Burn this diagram in:

```
        chat_handle_join                         chat_message_join
   ┌──────────────────────┐                 ┌──────────────────────┐
   │ chat_id   handle_id  │                 │ chat_id   message_id │
   └─────┬───────────┬────┘                 └────┬──────────────┬──┘
         │           │                           │              │
     ┌───▼───┐   ┌───▼────┐                  ┌───▼───┐     ┌────▼─────┐
     │ chat  │   │ handle │                  │ chat  │     │ message  │
     │(thread│   │(a phone│                  │(thread│     │ (a text) │
     │ /room)│   │ /email)│                  │ /room)│     └────┬─────┘
     └───────┘   └────────┘                  └───────┘          │
                                                    message_attachment_join
                                                      ┌─────────▼──────────┐
                                                      │ message_id  attach_id│
                                                      └─────────┬───────────┘
                                                            ┌───▼────────┐
                                                            │ attachment │
                                                            └────────────┘
```

| Table | Role | Key columns |
|---|---|---|
| `message` | One row per message (sent or received) | `ROWID`, `guid`, `text`, `attributedBody`, `handle_id`, `service`, `date`, `date_read`, `date_delivered`, `is_from_me`, `message_summary_info`, `date_edited`, `date_retracted`, `associated_message_guid` |
| `handle` | One row per remote *identifier* (a phone number or Apple ID email), per service | `ROWID`, `id`, `service`, `country`, `uncanonicalized_id` |
| `chat` | One row per conversation thread (1:1 or group) | `ROWID`, `guid`, `chat_identifier`, `display_name`, `room_name`, `group_id`, `service_name`, `style` |
| `attachment` | One row per file sent/received | `ROWID`, `guid`, `filename`, `mime_type`, `transfer_name`, `total_bytes`, `created_date`, `is_sticker` |
| `chat_message_join` | Maps **live** messages to chats | `chat_id`, `message_id` |
| `chat_handle_join` | Maps participants to chats | `chat_id`, `handle_id` |
| `message_attachment_join` | Maps attachments to messages | `message_id`, `attachment_id` |
| `chat_recoverable_message_join` | iOS 16+ "Recently Deleted" link (30-day window) | `chat_id`, `message_id`, `delete_date` |

Two structural points that trip people up:

- **A single human is many `handle` rows.** Alice's iPhone number, her iCloud email, and the same number seen over SMS vs iMessage can each be a distinct `handle.ROWID`. Attribution requires deduplicating handles by `id` (and reconciling against the Contacts store — see [[call-history-voicemail-contacts-interactions]]).
- **`message.handle_id` is the *remote* party only.** For an outbound message (`is_from_me = 1`) it identifies the recipient/thread, not the sender; in group chats it is frequently `0`. Direction comes from `is_from_me`, never from `handle_id`.

### Anatomy of the `message` table

The forensically load-bearing columns:

| Column | Meaning / gotcha |
|---|---|
| `ROWID` | Integer primary key. **Reused** after deletion — do not treat as a stable identity across time. |
| `guid` | Globally unique message ID (UUID string). The stable identity; also referenced by tapbacks/replies/edits via `associated_message_guid`. |
| `text` | Plaintext body. **Frequently `NULL` on modern messages** — the body is in `attributedBody`. |
| `attributedBody` | `BLOB` — a `typedstream`-archived `NSAttributedString` holding the real body when `text` is `NULL` (see below). |
| `service` | `'iMessage'`, `'SMS'`, or (iOS 18+) `'RCS'`. The single best iMessage-vs-carrier discriminator. *(Exact `'RCS'` string worth confirming on your image — RCS landed in iOS 18 (2024) and gained default E2EE in iOS 26.5 (May 2026) via RCS Universal Profile 3.0.)* |
| `is_from_me` | `1` = outbound, `0` = inbound. The authoritative direction flag. |
| `date` | Send/receive time — **nanosecond Mac-Absolute** (see epoch section). |
| `date_read` | When *you* read an inbound msg, or when the remote read *your* outbound msg (read receipt). `0` = never/unknown. |
| `date_delivered` | Delivery receipt time. `0` = not delivered. |
| `date_edited` | iOS 16+ — set when an iMessage is edited. |
| `date_retracted` | iOS 16+ — column exists for "Undo Send" but Apple has historically **not populated it**; retraction is inferred elsewhere. *(Verify on your image.)* |
| `message_summary_info` | `BLOB` (binary plist) — edit/version history and the **pre-edit original text** (see Edits & Unsends). |
| `associated_message_guid` / `associated_message_type` | Tapbacks (Liked/Loved/…), inline replies, edits reference a parent message. Type codes ~2000–2005 add a reaction, ~3000–3005 remove it. |
| `balloon_bundle_id` | Non-text "app" messages (Apple Pay, polls, stickers, third-party iMessage apps). |
| `item_type` / `group_title` | Group-management events (renames, joins/leaves) rather than text. |
| `thread_originator_guid` | Inline-reply threading (iOS 14+) — links a reply to the message it answers. |

### The nanosecond Mac-Absolute epoch — the classic 30-year trap

Apple timestamps in `sms.db` use **Mac-Absolute Time**: seconds since `2001-01-01 00:00:00 UTC` (Cocoa/Core Data reference date), **not** the Unix 1970 epoch. The offset between the two is `978307200` seconds.

Since **iOS 11 / macOS 10.13 High Sierra (2017)**, the `date`, `date_read`, `date_delivered`, and `date_edited` columns are stored in **nanoseconds**, not seconds. So the full conversion is:

```
unix_seconds = (mac_absolute_nanoseconds / 1000000000) + 978307200
```

Two distinct ways to get it wrong, each with a signature failure:

- **Forget the `/1e9` (the nanosecond divide):** you treat ~7×10¹⁷ as seconds. The result lands tens of thousands of years in the future (or overflows to garbage). Signature: dates like year 50,000+.
- **Forget the `+978307200` (the epoch offset):** you treat Mac-Absolute seconds as Unix seconds and every timestamp is shifted **~31 years early** (2001 vs 1970). Signature: a 2024 conversation that renders in 1993. This is the "30-year-off" trap the macOS course warned you about — same bug, same store family.

A defensive, magnitude-aware expression handles legacy rows that may still be in seconds (rare migrated/SMS rows, and pre-iOS-11 data):

```sql
-- If the value is "big" it's nanoseconds; if "small" it's already seconds.
datetime(
  CASE WHEN message.date > 1000000000000   -- ~> 1e12 ⇒ nanoseconds
       THEN message.date / 1000000000
       ELSE message.date
  END + 978307200, 'unixepoch', 'localtime'
) AS sent
```

> 🔬 **Forensics note:** Always convert receipts conditionally — `date_read`/`date_delivered` of `0` means *never read / never delivered*, and blindly applying the epoch to `0` yields a fake "2001-01-01" that looks like real evidence. Wrap them: `CASE WHEN date_read > 0 THEN datetime(...) END`. A false read-receipt timestamp has lost cases.

### `attributedBody` and the `typedstream` format

On modern iOS, the human-readable body of most iMessages is **not** in `text` — that column is `NULL` and the content lives in the `attributedBody` `BLOB`. This is the number-one reason naïve `SELECT text FROM message` exports come back half-empty.

`attributedBody` is a serialized `NSAttributedString` — but **not** a binary plist and **not** an `NSKeyedArchiver` archive. It is the legacy NeXT/Apple **`typedstream`** format (the old `NSArchiver`/`streamtyped` serialization). You can confirm it by eye: every blob begins with the magic bytes

```
04 0B 73 74 72 65 61 6D 74 79 70 65 64   →  "....streamtyped"
```

Walk the head of a real blob and the structure becomes legible — the body string sits a fixed distance past a recognizable `NSString`/`NSMutableString` class marker:

```
04 0b 73 74 72 65 61 6d 74 79 70 65 64   "..streamtyped"   ← archive magic + version
81 e8 03 84 01 40 84 84 84 12 4e 53 ...   ...NSString class chain (NSAttributedString →
                                            NSMutableString → NSObject)
... 84 01 2b 86 84 01 2a <len> <UTF-8 bytes of the message text> ...
... 84 02 69 49 ... NSDictionary of attribute runs (link, mention, send-style ranges) ...
```

The `2b`/`2a` type tags introduce the inline string and its length; the trailing dictionary holds the *attribute runs* — URL link ranges, `@`-mention person references, invisible-ink/send-with-effect markers — which is metadata you lose entirely with a plain string grep. Because it is `typedstream` and not a plist, `plutil`, `plistlib`, and any "convert to XML plist" reflex **fail** — that mismatch is exactly what fools tools and examiners into reporting empty messages. The body is recoverable three ways, in increasing robustness:

1. **String-scan** the blob for the embedded `NSString` (quick, fragile — breaks on formatting/Unicode and silently truncates).
2. **A real `typedstream` parser** — `pytypedstream` (dgelessus), the `typedstream` Rust crate, or `imessage_tools`. This recovers text *plus* the attribute runs (mentions, links, formatting ranges).
3. **A purpose-built exporter** — `imessage-exporter` (ReagentX) decodes `attributedBody`, walks every join, and resolves edits/tapbacks/attachments; it's the current community gold standard and works identically on iOS `sms.db` and macOS `chat.db`.

> 🔬 **Forensics note:** When `text` is populated *and* `attributedBody` exists, prefer `attributedBody` — it carries the formatting, embedded mentions, and the URL of link previews. And when reporting, note which field you sourced each message from; "text was NULL, body recovered from attributedBody typedstream" is the kind of provenance that survives cross-examination.

### `handle`, `chat`, and the attachment tree

**`handle`** maps a numeric `ROWID` to an `id` — a phone number (E.164, e.g. `+15551234567`) or an Apple ID email — qualified by `service`. The same person reachable by phone *and* email *and* over both SMS and iMessage produces multiple rows; `uncanonicalized_id` preserves the number as originally seen.

**`chat`** is the thread. `chat_identifier` is the other party (1:1) or a synthetic group id like `chat678901234567890`. `style` distinguishes them — `45` = a 1:1 conversation, `43` = a group chat. `display_name`/`room_name`/`group_id` carry group naming. A given remote party can have several `chat` rows over time (e.g. a thread re-created after deletion).

**Attachments** are stored as real files under `/private/var/mobile/Library/SMS/Attachments/`, in a **path-sharded** tree to avoid one giant flat directory:

```
Attachments/<h>/<hh>/<GUID>/<transfer_name>
e.g.  Attachments/a/0b/3F2A...-D41C/IMG_4417.HEIC
```

The shard is taken from the attachment's GUID (one hex nibble, then two hex chars, then the full GUID directory). The `attachment.filename` column stores the on-device absolute path (rooted at `~/Library/SMS/Attachments/...` i.e. `/var/mobile/Library/...`); `mime_type`, `transfer_name`, `total_bytes`, and `created_date` (nanosecond epoch) round out the metadata. You reach an attachment from a message via `message_attachment_join`.

> 🔬 **Forensics note:** When you carry an extraction off the device, the absolute paths in `attachment.filename` no longer resolve. Rebase them onto your evidence mount point, and watch for **orphaned attachment files** — media physically present in `Attachments/` whose `attachment` row (or its join) was deleted. The file outliving its database row is itself evidence the conversation was tampered with.

### Tapbacks, replies, and the conversation graph

Not every `message` row is a sentence someone typed. iMessage overlays a small graph on top of the linear thread, and reconstructing it correctly is the difference between "Bob said X" and "Bob *reacted to* X." The two columns that build the graph are `associated_message_guid` (the `guid` of the message being acted upon) and `associated_message_type` (what the action was):

| `associated_message_type` | Meaning |
|---|---|
| `0` | A normal message (no association). |
| `1000` | A **sticker** placed onto a message bubble (associated to its target via `associated_message_guid` — *not* a reaction). |
| `2000–2005` | **Add** a tapback — Loved, Liked, Disliked, Laughed, Emphasized, Questioned (in that order). |
| `2006 / 2007` | iOS 18+ — **add** a custom-**emoji** tapback / a **sticker** tapback. |
| `3000–3005` | **Remove** the corresponding `2000–2005` tapback. |
| `3006 / 3007` | iOS 18+ — **remove** the emoji / sticker tapback. |

`associated_message_guid` itself sometimes carries a prefix — `p:N/<guid>` points at the *Nth body component* of the target (text segment or the Nth attachment; a Like on `p:2/` reacts to the third image), while `bp:<guid>` points at a *bubble* component (a URL preview, Apple Pay, or app message). Strip the prefix before joining back to `message.guid`. Inline **replies** (iOS 14+) are threaded separately via `thread_originator_guid`, which links a reply to the message it answers and lets you rebuild the nested reply tree rather than a flat scroll.

```sql
-- Resolve tapbacks to the message they reacted to
SELECT
  datetime(r.date/1000000000+978307200,'unixepoch','localtime') AS when_reacted,
  CASE r.is_from_me WHEN 1 THEN 'ME' ELSE h.id END               AS reactor,
  r.associated_message_type                                      AS tb_code,
  COALESCE(t.text,'[parent body in attributedBody]')            AS reacted_to
FROM message r
LEFT JOIN handle  h ON r.handle_id = h.ROWID
LEFT JOIN message t ON t.guid = replace(replace(r.associated_message_guid,'p:0/',''),'bp:','')
WHERE r.associated_message_type BETWEEN 2000 AND 3007   -- 2006/2007 + 3006/3007 = iOS 18 emoji/sticker tapbacks
ORDER BY r.date DESC LIMIT 30;
```

> 🔬 **Forensics note:** A naïve export that treats tapbacks as ordinary messages produces phantom lines ("Loved 'see you at 8'") attributed to the wrong intent, and inflates message counts. Conversely, a *missing* tapback whose parent still exists, or a reaction `associated_message_guid` that resolves to nothing, is a tampering tell — someone deleted the parent but left the reaction, or vice versa.

### Group chats and participant reconstruction

In a 1:1 thread, attribution is easy: `is_from_me` plus the single `handle`. Group chats are where examiners go wrong, because `message.handle_id` in a group identifies *the chat's other party generally* (often `0` for your own messages) and is useless for "who in the group said this." The correct model: the **roster** of a group comes from `chat_handle_join` (every participant ever in that `chat`), while the **author of each inbound message** comes from that message's own `handle_id` resolved against `handle`. Membership is also not static — `item_type`/`group_title` rows record renames and join/leave events as pseudo-messages in the timeline, so the roster you see today may differ from who was present when a given message was sent.

```sql
-- Roster of a group chat + its display name
SELECT c.ROWID, c.display_name, c.chat_identifier, h.id AS participant
FROM chat c
JOIN chat_handle_join chj ON c.ROWID = chj.chat_id
JOIN handle h             ON chj.handle_id = h.ROWID
WHERE c.style = 43          -- group chats only
ORDER BY c.ROWID, h.id;
```

> 🔬 **Forensics note:** Reconcile every `handle.id` against the device's address book (`AddressBook.sqlitedb`, see [[call-history-voicemail-contacts-interactions]]) before naming a participant in a report. A bare `+15551234567` is an *identifier*, not a *person* — the same human may appear under several handles, and a number can be reassigned. Attribution that skips the contacts reconciliation is attribution a defense expert will dismantle.

### iMessage vs SMS vs RCS, Continuity, and Messages in iCloud

The `service` column is your protocol discriminator. `'iMessage'` is Apple's E2EE service (blue); `'SMS'`/`'MMS'` is carrier (green); iOS 18 (2024) added **`'RCS'`** (carrier RCS) — default **E2EE** for RCS arrived later, in **iOS 26.5** (May 2026), via RCS Universal Profile 3.0 built on the MLS protocol. All three land in the *same* `sms.db` regardless of transport — the encryption is in transit; **at rest on the endpoint, the body is plaintext** (subject to file-system Data Protection, not message-level crypto).

Two architecture facts change *what you even have*:

- **Continuity / Text Message Forwarding** mirrors SMS to the user's other Apple devices, and **Messages in iCloud** keeps `sms.db` in sync across devices and the cloud. If Messages in iCloud is enabled, the on-device `sms.db` may be a **thinned cache** — older messages and full attachments live in iCloud (CloudKit), and full recovery means cloud acquisition (see [[icloud-acquisition-and-advanced-data-protection]]). ADP (Advanced Data Protection) E2EE-encrypts that iCloud copy and removes the cloud path entirely.
- The **paired Mac** holds the same content in `chat.db`. Cross-device corroboration both strengthens a timeline and exposes tampering (a message present on the Mac but scrubbed from the phone).

### Edits and unsends (iOS 16+) — the original text survives

iOS 16 added message **editing** and **Undo Send** (unsend). Both blank the visible body in the live row — but the prior content is retained:

- **Editing** writes `date_edited` and stores the **full version history**, including the *original* pre-edit text, in the `message_summary_info` binary-plist `BLOB`. You can reconstruct exactly what was first sent and every subsequent edit with timestamps.
- **Unsending** removes the message from the conversation view, but the row (and frequently its `attributedBody`/`message_summary_info`) lingers in the database and the WAL well past the user's intent. Chris Vance (d204n6) documented that "Paul unsent a message" does **not** mean Paul's words are gone — they're recoverable from the blob and from corroborating stores. Note `date_retracted` exists but Apple has not reliably populated it, so do not rely on its presence to *detect* an unsend; detect it from `message_summary_info` and the conversation-view delta.

> 🔬 **Forensics note:** `message_summary_info` is a binary plist (so here `plutil -convert xml1` *does* work, unlike `attributedBody`). Extract it with `SELECT writefile('/tmp/msi.plist', message_summary_info) ...` then `plutil -p`. The original text of an edited or unsent message is one of the highest-value recoveries in iOS comms forensics — it captures intent the sender tried to retract.

### Recently Deleted (iOS 16+) and deeper deletion recovery

Deletion on modern iOS is a layered affair, and each layer is a recovery opportunity. Picture a message falling through a series of nets, each holding it for a while:

```
user deletes a message
        │
        ▼
[1] Recently Deleted  ──────── row intact; re-linked to chat_recoverable_message_join
        │  (30 days, or user "Delete" in that folder)         (delete_date set)
        ▼
[2] sms.db-wal        ──────── last row image sits in uncheckpointed WAL frames
        │  (until checkpoint + page reuse)
        ▼
[3] freelist / unallocated B-tree pages ── carvable record until VACUUM/overwrite
        │
        ▼
[4] gone from sms.db ─ but copies persist in Biome/SEGB + the notification store
```

Each layer in turn:

1. **Recently Deleted (iOS 16+).** Deleting a message doesn't remove it — it **unlinks the row from `chat_message_join` and links it into `chat_recoverable_message_join`** with a `delete_date`, keeping it for **30 days** (the user-visible "Recently Deleted" folder). The `message` row is fully intact: text/attributedBody, sender, timestamps. This is trivially recoverable by querying through the recoverable join instead of the normal one — yet many conversation-view tools only walk `chat_message_join` and report these as gone.
2. **Pending-purge bookkeeping.** A `deleted_messages` table tracks GUIDs of messages slated for removal/sync reconciliation; its presence flags churn even when bodies are gone. *(Exact role varies by version — confirm on your image.)*
3. **The WAL.** Messages permanently deleted (or aged out of Recently Deleted) leave their last-written image in `sms.db-wal` until checkpointed and overwritten. The WAL is a sequence of **frames**, each a 24-byte frame header (page number + salt/checksum) followed by one full 4 KB database page. A delete doesn't scrub the page — SQLite writes a *new* version of the B-tree page with the cell removed, but the *prior* frame containing the live cell still sits earlier in the WAL. Carving frames in order, newest-wins per page number, recovers full deleted rows — body, handle, timestamps, sometimes attachment references — that exist in *no* version of the main file. This is precisely the content an auto-checkpoint destroys, which is why you carve the `-wal` before any client opens the set.
4. **Unallocated / freelist pages.** Once checkpointed and the row deleted, the record persists in unallocated B-tree pages and the freelist until SQLite reuses the space (no `VACUUM`/overwrite yet). SQLite record carvers reconstruct these even with no live row.
5. **Cross-store corroboration.** Message content is duplicated outside `sms.db`: into **Biome/SEGB streams** (`/private/var/mobile/Library/Biome/streams/...`, e.g. `AppIntent` — see [[biome-and-segb-streams]]) and into the **notification (push) store**. The notification angle is freshly load-bearing: **CVE-2026-28950** (patched in iOS/iPadOS 26.4.2 and 18.7.8, 2026-04-22) was a logging flaw in Apple's Notification Services where notifications *marked for deletion were never actually redacted* and lingered in the internal notification store — the FBI recovered deleted **Signal** message previews from that store despite the app having been removed (Apple's fix was described as "improved data redaction"). Even patched, the notification store remains a corroborating copy of `sms.db` previews (see [[notifications-keyboard-and-misc-stores]]).

> ⚖️ **Authorization:** Recovering deleted and unsent content — especially from a paired Mac, an iCloud copy, or a third party's messages within the thread — frequently exceeds the literal scope of a "review the texts" request. Confirm your legal authority covers *deleted* data and *both sides* of the conversation, document the recovery method per message, and keep the body-source provenance (live row vs Recently-Deleted join vs WAL carve vs notification store) in your notes. Reconstructed evidence with murky provenance gets suppressed.

### What the schema leaves out: drafts, stickers, and sync state

Three peripheral stores in the `SMS/` directory carry evidence that lives *outside* the `message` table:

- **`Drafts/`** — one subfolder per thread (named by chat GUID) holding a `composing.plist` binary plist with the user's **unsent draft text** and pending attachments. This is intent that was *never sent* and therefore appears nowhere in `message` — frequently the most revealing artifact in the whole store. `plutil -p Drafts/<guid>/composing.plist` reads it directly.
- **`Attachments/` vs `StickerCache/`** — inline stickers and Memoji are cached separately; an `attachment` row with `is_sticker = 1` points into this space rather than ordinary media.
- **`_SqliteDatabaseProperties`** — a key/value table inside `sms.db` recording sync and feature state (e.g. Messages-in-iCloud enablement, schema/version markers). A row indicating iCloud sync is on is your cue that the local store may be thinned and that an iCloud copy exists.

> 🔬 **Forensics note:** A populated `composing.plist` next to an *empty* thread, or a draft whose text matches a later "unsent" message, ties intent to action across two independent stores. Always enumerate `Drafts/` — tools that parse only `sms.db` walk straight past it.

## Hands-on

There is no on-device shell. Everything below runs **on the Mac** against an acquired copy (or, for schema/format work, against your own Mac's `chat.db` twin). Copy the triplet first, every time:

```bash
# Acquire the inseparable set into an evidence dir, then hash it
mkdir -p ~/Downloads/sms-forensics/evidence
cp /path/to/extraction/private/var/mobile/Library/SMS/sms.db*   ~/Downloads/sms-forensics/evidence/
shasum -a 256 ~/Downloads/sms-forensics/evidence/sms.db*        > ~/Downloads/sms-forensics/evidence/SHA256SUMS
```

**Confirm journal mode and inspect the schema (read-only):**

```bash
sqlite3 -readonly ~/Downloads/sms-forensics/evidence/sms.db \
  "PRAGMA journal_mode; .tables"
# wal
# _SqliteDatabaseProperties  chat_handle_join          handle
# attachment                 chat_message_join         message
# chat                       chat_recoverable_message_join  message_attachment_join
# ...
```

> ⚠️ **ADVANCED:** `sqlite3 -readonly` avoids *writing* but a normal open of a WAL database can still **checkpoint** and lose recoverable deleted frames. For recovery work, carve `sms.db-wal` with a dedicated tool (below) *before* any client touches the set. `-readonly` is for the live-row queries here, not for deleted-data recovery.

**Reconstruct full conversations — participants, direction, body, receipts:**

```bash
sqlite3 -readonly ~/Downloads/sms-forensics/evidence/sms.db <<'SQL'
.mode box
.headers on
SELECT
  datetime(m.date/1000000000 + 978307200,'unixepoch','localtime')      AS sent,
  c.chat_identifier                                                    AS thread,
  CASE m.is_from_me WHEN 1 THEN 'ME' ELSE h.id END                     AS sender,
  m.service                                                            AS svc,
  COALESCE(m.text,'[body in attributedBody — decode separately]')      AS body,
  CASE WHEN m.date_read>0
       THEN datetime(m.date_read/1000000000+978307200,'unixepoch','localtime')
       END                                                             AS read_at
FROM message m
JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
JOIN chat   c              ON cmj.chat_id = c.ROWID
LEFT JOIN handle h         ON m.handle_id = h.ROWID
ORDER BY m.date
LIMIT 40;
SQL
```

**List attachments for a thread:**

```bash
sqlite3 -readonly ~/Downloads/sms-forensics/evidence/sms.db "
SELECT m.ROWID, a.mime_type, a.total_bytes, a.transfer_name, a.filename
FROM message m
JOIN message_attachment_join maj ON m.ROWID = maj.message_id
JOIN attachment a                ON maj.attachment_id = a.ROWID
ORDER BY a.created_date DESC LIMIT 20;"
```

**Dump and identify an `attributedBody` blob:**

```bash
# Pull one NULL-text body to a file and prove it's typedstream, not a plist
ROWID=$(sqlite3 -readonly evidence/sms.db \
  "SELECT ROWID FROM message WHERE text IS NULL AND attributedBody IS NOT NULL LIMIT 1;")
sqlite3 -readonly evidence/sms.db \
  "SELECT writefile('/tmp/ab.bin', attributedBody) FROM message WHERE ROWID=$ROWID;"
xxd /tmp/ab.bin | head -1
# 00000000: 040b 7374 7265 616d 7479 7065 6420 8401  ..streamtyped ..
plutil -p /tmp/ab.bin            # FAILS — not a plist. Proves the format.
```

**Decode bodies + edits + tapbacks the right way (community tooling):**

```bash
brew install imessage-exporter          # or: cargo install imessage-exporter
imessage-exporter --db-path ~/Downloads/sms-forensics/evidence/sms.db \
                  --format txt \
                  --export-path ~/Downloads/sms-forensics/export
# Walks every join, decodes attributedBody/typedstream, resolves edits,
# unsends, tapbacks, replies, and attachments — works on iOS sms.db
# and macOS chat.db unchanged.
```

**Recover the original text of an edited/unsent message:**

```bash
sqlite3 -readonly evidence/sms.db \
  "SELECT writefile('/tmp/msi.plist', message_summary_info)
   FROM message WHERE date_edited > 0 LIMIT 1;"
plutil -p /tmp/msi.plist        # binary plist DOES decode — shows edit/version history
```

**Carve deleted rows from the WAL (out-of-band, no checkpoint):**

```bash
# Community SQLite/WAL carvers — pick per your kit:
python3 walitean.py sms.db                     # WAL/freelist string carver
#   or
sqlite3 sms.db .recover > /tmp/recovered.sql    # SQLite's own structural recovery
#   commercial: Sanderson Forensic Browser / SQLite Forensic Toolkit, CCL Epilog,
#   Magnet AXIOM, Cellebrite PA — all do WAL + freelist record recovery.
```

## 🧪 Labs

> **Substrate doctrine for this lesson.** The iOS **Simulator does not ship Messages.app** (nor Phone), so you cannot generate a real `sms.db` on the Simulator — do not try. Instead, the labs use three device-free substrates: **(A)** your own Mac's `~/Library/Messages/chat.db` — the *same schema, same epoch, same typedstream blobs*, ideal for joins/format work; **(B)** a **public iOS reference image** (Josh Hickman's iOS images on thebinaryhick.blog / Digital Corpora, or the iLEAPP test data) for the iOS-specific Recently-Deleted / path-sharded-Attachments behaviour; **(C)** a **synthetic `sms.db`** you build to safely practice WAL carving. None of these requires a physical iPhone. Fidelity caveat: the Mac twin has no Data-Protection-at-rest and no iOS-only columns populated the same way; trust the *structure* it teaches, and read iOS-specific deletion/encryption behaviour from substrate B.

### Lab 1 — Joins, epoch, and direction on the macOS twin (substrate A)

1. `cp ~/Library/Messages/chat.db* /tmp/lab1/` (copy the triplet; never query the original).
2. `sqlite3 -readonly /tmp/lab1/chat.db "PRAGMA journal_mode;"` — confirm `wal`.
3. Run the full conversation-reconstruction query from Hands-on. Verify timestamps render in *this decade* — if they show year ~50000 you forgot `/1e9`; if ~1993 you forgot `+978307200`.
4. Find a message where `text IS NULL AND attributedBody IS NOT NULL`. Confirm modern bodies hide in the blob.
5. Count distinct `handle.id` vs distinct `handle.ROWID`. Explain why the same person can be several handles.

### Lab 2 — Decode an `attributedBody` typedstream (substrate A)

1. From `/tmp/lab1/chat.db`, `writefile` one NULL-text `attributedBody` to `/tmp/ab.bin`.
2. `xxd /tmp/ab.bin | head` — confirm the `streamtyped` magic. Run `plutil -p /tmp/ab.bin` and watch it fail (proves it is *not* a plist).
3. Recover the text three ways and compare: (a) `strings /tmp/ab.bin` (note the fragility/truncation), (b) `pip install pytypedstream` and parse it properly, (c) run `imessage-exporter` over the whole copy and find the same message — confirm all three agree on the body, but only (b)/(c) preserve formatting/links.

### Lab 3 — Recently Deleted + attachments on a real iOS image (substrate B)

1. Acquire a public iOS reference `sms.db` (Hickman image / iLEAPP test data).
2. Run two conversation queries: one joining through `chat_message_join` (live), one through `chat_recoverable_message_join` (Recently Deleted). Diff the message sets — the delta is the 30-day deleted pool, with `delete_date` decoded via the nanosecond epoch.
3. Pick an attachment row; reconstruct its on-disk path under `Attachments/<h>/<hh>/<GUID>/` and confirm the file exists in the image. Then hunt for an **orphaned** attachment file whose `attachment`/join row is gone.
4. If the image has edited messages, `writefile` a `message_summary_info`, `plutil -p` it, and recover the original pre-edit text.

### Lab 4 — Build and carve a WAL (substrate C)

1. Create a synthetic store and force WAL mode:
   ```bash
   sqlite3 /tmp/syn.db "PRAGMA journal_mode=WAL;
     CREATE TABLE message(ROWID INTEGER PRIMARY KEY, guid TEXT, text TEXT,
       handle_id INT, service TEXT, date INT, is_from_me INT);"
   for i in $(seq 1 50); do
     sqlite3 /tmp/syn.db "INSERT INTO message(guid,text,handle_id,service,date,is_from_me)
       VALUES('G$i','secret message $i', $((i%5)), 'iMessage',
              $(( (RANDOM*1000000000) )), $((i%2)));"
   done
   ```
2. Delete a chunk *without* checkpointing: `sqlite3 /tmp/syn.db "DELETE FROM message WHERE ROWID<=20;"` then immediately `ls -l /tmp/syn.db*` — note the live `-wal`.
3. Carve the deleted rows back: try `strings /tmp/syn.db-wal | grep 'secret message'`, then a structured carver (`walitean.py` or `sqlite3 /tmp/syn.db .recover`). Confirm you recover the bodies of rows that no longer exist live.
4. Now `sqlite3 /tmp/syn.db "PRAGMA wal_checkpoint(TRUNCATE);"` and re-carve — observe how checkpointing changes what's recoverable from the WAL vs the freelist. This is *why* you never let a client checkpoint evidence.

### Lab 5 — Cross-store corroboration & tampering detection (substrate B)

1. On a public iOS image, run `imessage-exporter` for a clean baseline conversation export.
2. **Handle reconciliation:** join `handle.id` against the image's `AddressBook.sqlitedb`. Produce a table mapping each handle to a named contact (or flag it "unknown identifier"). Note any human represented by more than one handle.
3. **Tapback graph:** run the tapback-resolution query; confirm every reaction's `associated_message_guid` resolves to an existing parent. Any reaction pointing at a missing parent is a deletion artifact — log it.
4. **Orphan hunt:** list files under `Attachments/` and diff against `attachment.filename`. Files with no row = orphaned media (deleted row, surviving file). Rows with no file = pruned media (surviving metadata, deleted file). Both are evidence.
5. **Second source:** for one conversation, pull the same message text from a Biome/SEGB stream ([[biome-and-segb-streams]]) and/or the notification store ([[notifications-keyboard-and-misc-stores]]). Where the corpora disagree (present in Biome, absent from `sms.db`) you've found content the user deleted from Messages but failed to scrub everywhere — the strongest form of deleted-message proof.

## Pitfalls & gotchas

- **Copying only `sms.db`.** Dropping the `-wal`/`-shm` before recovery silently discards every uncheckpointed deleted message. Always acquire the triplet; carve the WAL before any open.
- **`SELECT text` exports.** Modern bodies are `NULL` in `text` and hidden in `attributedBody`. A `text`-only export under-reports the conversation, sometimes by most of it.
- **Treating `attributedBody` as a plist.** It is `typedstream`/`streamtyped`, not a binary plist and not `NSKeyedArchiver` — `plutil`/`plistlib` fail. Use a `typedstream` parser. (`message_summary_info`, by contrast, *is* a binary plist.)
- **Epoch errors.** Forgetting `/1e9` → far-future dates; forgetting `+978307200` → ~31-year-early dates. And never epoch-convert a `0` receipt — it fabricates a `2001-01-01` "read" time.
- **`handle_id` ≠ sender.** It's the remote/thread identifier; in groups it's often `0`. Direction is `is_from_me`. Sender in a group comes from the per-message handle, not the chat.
- **`ROWID` reuse.** Deleted-then-inserted rows reuse integer `ROWID`s; correlate on `guid` for stable identity across acquisitions.
- **Messages in iCloud thinning.** When enabled, on-device `sms.db` can be a partial cache — older content is in iCloud. ADP removes the cloud path. Don't conclude "the user had few messages" from a thinned local store; check the iCloud posture (see [[icloud-acquisition-and-advanced-data-protection]]).
- **Recently-Deleted blind spots.** Tools that only walk `chat_message_join` miss the `chat_recoverable_message_join` pool — up to 30 days of "deleted" messages reported as gone.
- **Assuming "unsent" means erased.** Edited/unsent originals survive in `message_summary_info`, the WAL, Biome/SEGB, and the notification store. Don't accept the conversation view at face value.
- **Ignoring `Drafts/`.** Unsent intent lives in `composing.plist`, not the `message` table; a `sms.db`-only workflow misses it entirely.
- **Conflating tapbacks with messages.** Reaction rows (`associated_message_type` 2000–3007), sticker-placement rows (`1000`), and group-management rows (`item_type`) are not sentences — count and render them separately or your transcript is wrong.
- **Assuming green = unencrypted in transit forever.** iOS 18 RCS and iOS 26.5's default RCS E2EE change *transit* protection, but the `service` string and at-rest plaintext in `sms.db` are what you analyze; don't infer transport security from the local row.
- **Anti-forensics signal:** an orphaned `Attachments/` file with no `attachment` row, a `deleted_messages` table full of GUIDs, or a freshly `VACUUM`ed `sms.db` (no freelist, suspiciously tidy) all indicate deliberate cleanup.

## Key takeaways

- `sms.db` at `/private/var/mobile/Library/SMS/sms.db` is one WAL-mode SQLite store holding iMessage, SMS, and (iOS 18+) RCS — acquire the `sms.db`/`-wal`/`-shm` triplet as one evidence set.
- The schema is many-to-many: `message`⇄`chat` via `chat_message_join`, participants via `chat_handle_join`/`handle`, files via `message_attachment_join`/`attachment`. Direction is `is_from_me`; `handle_id` is the remote party.
- Timestamps are **nanosecond Mac-Absolute**: `date/1e9 + 978307200`. Forgetting the divide throws dates millennia out; forgetting the offset throws them ~31 years early.
- Modern message bodies are usually `NULL` in `text` and stored in `attributedBody` as **`typedstream`** (`streamtyped`) — not a plist; decode with a real `typedstream` parser or `imessage-exporter`.
- iOS 16+ edits/unsends retain the **original text** in `message_summary_info` (a binary plist); recover it.
- "Recently Deleted" (iOS 16+) keeps deleted messages 30 days in `chat_recoverable_message_join`; deeper deletions are carved from the WAL, freelist, and corroborated by Biome/SEGB and the notification store (cf. CVE-2026-28950).
- The paired Mac's `chat.db` and Messages-in-iCloud are second copies of the same conversations — corroboration and a route around a locked phone.

## Terms introduced

| Term | Definition |
|---|---|
| `sms.db` | The iOS SQLite store for all text messaging (iMessage/SMS/RCS) at `/private/var/mobile/Library/SMS/sms.db`. |
| WAL (write-ahead log) | SQLite journal mode where new/deleted rows live in a `-wal` sidecar until checkpointed; primary source of recoverable deleted messages. |
| `chat_message_join` | Many-to-many link between live messages and conversation threads. |
| `chat_recoverable_message_join` | iOS 16+ link table holding "Recently Deleted" messages for 30 days, with `delete_date`. |
| `message_attachment_join` | Many-to-many link between messages and attachment files. |
| Mac-Absolute Time | Apple timestamp epoch of 2001-01-01 UTC; add `978307200` to reach Unix time. |
| Nanosecond epoch (iOS 11+) | Since iOS 11 / macOS 10.13, `sms.db` date columns are nanoseconds — divide by 1e9 before applying the offset. |
| `attributedBody` | `BLOB` holding the `NSAttributedString` message body when `text` is `NULL`. |
| `typedstream` / `streamtyped` | Legacy `NSArchiver` serialization (magic `streamtyped`) used by `attributedBody`; not a plist, not `NSKeyedArchiver`. |
| Tapback | An iMessage reaction (Loved/Liked/…) stored as its own `message` row linking to a parent via `associated_message_guid`; type codes 2000–3007 (2006/2007 = iOS 18 custom-emoji / sticker tapbacks). |
| `associated_message_guid` | Column linking a tapback/reply/edit to the `guid` of the message it acts on (may carry a `p:N/` part prefix). |
| `thread_originator_guid` | Column (iOS 14+) linking an inline reply to the message it answers, enabling reply-tree reconstruction. |
| `composing.plist` | Per-thread binary plist under `SMS/Drafts/<guid>/` holding **unsent** draft text — intent that never reaches `message`. |
| `_SqliteDatabaseProperties` | Key/value table inside `sms.db` recording sync/feature state (e.g. Messages-in-iCloud enablement). |
| `message_summary_info` | Binary-plist `BLOB` retaining edit/version history and the original pre-edit text of edited/unsent messages. |
| `handle` | Table mapping a `ROWID` to a remote identifier (phone/email) per service; one person can be many handles. |
| `service` (column) | Protocol discriminator: `'iMessage'`, `'SMS'`/`'MMS'`, or (iOS 18+) `'RCS'`. |
| Recently Deleted | iOS 16+ 30-day soft-delete pool for messages, surfaced via `chat_recoverable_message_join`. |
| `imessage-exporter` | Community Rust tool (ReagentX) that decodes `typedstream` and walks every join for `sms.db`/`chat.db`. |
| CVE-2026-28950 | iOS Notification Services logging flaw (patched 26.4.2 / 18.7.8, 2026-04-22) — notifications marked for deletion weren't redacted, so deleted message previews lingered in the notification store; FBI recovered deleted Signal messages from a seized iPhone. |

## Further reading

- Apple Platform Security Guide — Messages in iCloud / iMessage key hierarchy; Apple Legal Process Guidelines (US) — Messages and iCloud production.
- Chris Vance (d204n6.com) — "iOS 16: 'Paul unsent a message.' … OR DID HE?!" (edit/unsend recovery, `message_summary_info`).
- Sarah Edwards (mac4n6.com) & APOLLO; Alexis Brignoni — iLEAPP (`github.com/abrignoni/iLEAPP`) SMS modules and test data.
- Sanderson Forensics (sqliteforensictoolkit.com) — "SMS recovered records and contacts" and "Why can't I see who sent that deleted iOS SMS message" (WAL/freelist recovery, handle linkage).
- Belkasoft — "Lagging for the Win: Querying for Negative Evidence in the sms.db."
- ReagentX — `imessage-exporter` (`github.com/ReagentX/imessage-exporter`) and its `typedstream` crate; `dgelessus/python-typedstream`; `my-other-github-account/imessage_tools`.
- Josh Hickman — iOS reference images (thebinaryhick.blog / Digital Corpora); NIST CFReDS mobile datasets.
- The Hacker News / Help Net Security (2026) — CVE-2026-28950 notification-retention coverage.
- `man sqlite3`; SQLite WAL & file-format docs (sqlite.org/walformat.html, sqlite.org/fileformat2.html).

---
*Related lessons: [[app-sandbox-and-filesystem-layout]] | [[biome-and-segb-streams]] | [[the-ios-timestamp-zoo]] | [[deleted-data-recovery]] | [[notifications-keyboard-and-misc-stores]] | [[call-history-voicemail-contacts-interactions]] | [[icloud-acquisition-and-advanced-data-protection]]*
