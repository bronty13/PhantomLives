---
title: SQL-Queries Index
type: reference-derived
description: Every SQLite query used across the course, grouped by source database, copy-paste-ready with the right epoch baked in
last_reviewed: 2026-06-26
---

# SQL-queries index

**Derived document** — rebuilt by combing the lesson corpus (see [HANDOFF.md](../HANDOFF.md)). Every `SELECT`
that appears in a lab is collected here, grouped by its source database, deduplicated, and annotated with
its purpose and the lesson it comes from.

## How to use this index

**Copy before you query — always.** A bare `SELECT` opens the database read-write, takes a write-lock, and
spawns `-wal`/`-shm` sidecars — that mutates evidence. Copy the store **and its sidecars** (`*.db`,
`*.db-wal`, `*.db-shm`, or `*.sqlite{,-wal,-shm}` / `*.sqlitedb` / `*.storedata{,-wal,-shm}`) to a working
directory, hash both, and run every query against the copy. Open read-only where you can:
`sqlite3 'file:copy.db?mode=ro' "…"`. (Note: deleted rows often survive **in the `-wal`** — see
[[14-deleted-data-recovery]] — so never discard the sidecars.)

**Pin the epoch first.** Most Apple stores use **Mac Absolute Time / Cocoa / CFAbsoluteTime** (seconds since
**2001-01-01 UTC**) → add `978307200` for Unix. But the corpus is full of traps: `sms.db`/`chat.db` are
Mac-Absolute **nanoseconds** (`/1e9` first); `TCC.db`, Mail `Envelope Index`, and `voicemail.date` are plain
**Unix** (no offset — adding 978307200 shifts you ~31 years to ~2057); browsers split across WebKit-1601 and
Firefox-PRTime. The per-DB headers below state which epoch applies; the [conversion-recipe
appendix](#timestamp-conversion-recipes-the-epoch-zoo) has every snippet. Full rationale: [[00-the-ios-timestamp-zoo]].

**Epoch cheat-sheet**

| Epoch | Convert to UTC | Seen in |
|---|---|---|
| Mac Absolute (2001), seconds | `+ 978307200` | knowledgeC, Photos, routined, Calendar, Notes, Reminders, AddressBook, CallHistory, interactionC, Safari, Accounts, netusage/DataUsage |
| Mac Absolute (2001), **nanoseconds** | `/1e9 + 978307200` | `sms.db`/`chat.db` `date*` columns (iOS 11+) |
| Unix (1970), seconds | none (`'unixepoch'`) | `TCC.db.last_modified`, Mail `Envelope Index`, `voicemail.date`, `Manifest.db` MBFile mtimes, PowerLog raw `TIMESTAMP` |
| Unix day-bucket (`DAYSSINCE1970`) | `*86400` | Aggregate Dictionary `ADDataStore.sqlitedb` |
| WebKit/Chrome (1601), microseconds | `/1e6 − 11644473600` | Chrome/Chromium `History`, some WebKit caches |
| Firefox PRTime (1970), microseconds | `/1e6` | Firefox `moz_places`/`moz_historyvisits` |

---

## Backup index — `Manifest.db`

> **Path:** `<UDID>/Manifest.db` at the root of an iTunes/Finder backup. **Copy first** (it has `-wal`/`-shm`).
> **Epoch:** the `Files` table itself stores no Cocoa dates; per-file mtimes live **as Unix seconds** inside
> each row's `MBFile` NSKeyedArchiver blob (`LastModified`/`LastStatusChange`/`Birth`). On an **encrypted**
> backup `Manifest.db` is AES-encrypted — decrypt with `mvt-ios decrypt-backup` (or Elcomsoft) before querying.
> This is the lookup table: `(domain, relativePath) → fileID`, where `fileID = SHA1(domain + "-" + relativePath)`
> and the blob lives at `<UDID>/<first-2-hex>/<fileID>`. Canonical fileIDs to confirm presence with a plain
> `ls`: `sms.db`=`3d0d7e5fb2ce288813306e4d4636395e047a3d28`,
> `CallHistory.storedata`=`5a4935c78a5255723f707230a451d79c540d2741`,
> `Photos.sqlite`=`12b144c0bd44f2b3dffd9186d3f9c05b917cee25`,
> `AddressBook.sqlitedb`=`31bb7ba8914766d4ba40d6dfb6113c8b614be442`.

**Domain census — top domains by file count** (orient in any backup) — [[10-device-services-and-backups]], [[05-backup-restore-migration-and-transfer]], [[00-ios-forensics-landscape-and-authorization]], [[07-decrypting-backups-and-images]]
```sql
SELECT domain, COUNT(*) FROM Files GROUP BY domain ORDER BY 2 DESC LIMIT 20;
```

**Full domain taxonomy** (every distinct domain) — [[01-the-acquisition-taxonomy]]
```sql
SELECT DISTINCT domain FROM Files;
```

**Third-party app containers in the backup** — [[05-backup-restore-migration-and-transfer]]
```sql
SELECT DISTINCT domain FROM Files WHERE domain LIKE 'AppDomain-%' ORDER BY 1;
```

**Encrypted-vs-plaintext tell** (Health present only if encrypted; Keychain present-but-locked) — [[05-backup-restore-migration-and-transfer]]
```sql
SELECT domain, COUNT(*) FROM Files WHERE domain IN ('HealthDomain','KeychainDomain') GROUP BY domain;
```

**Count regular files vs dirs vs symlinks** (`flags`: 1 = file, 2 = dir) — [[03-the-itunes-finder-backup-format]]
```sql
SELECT count(*), flags FROM Files GROUP BY flags;
```

**List all regular files** to reconstitute the logical tree (or use `idevicebackup2 unback`) — [[03-the-itunes-finder-backup-format]]
```sql
SELECT fileID, domain, relativePath FROM Files WHERE flags = 1;
```

**Inventory every SQLite-family store with its blob path** — [[03-the-itunes-finder-backup-format]]
```sql
SELECT domain, relativePath, fileID FROM Files
WHERE flags = 1 AND (relativePath LIKE '%.db' OR relativePath LIKE '%.sqlite'
                     OR relativePath LIKE '%.sqlitedb' OR relativePath LIKE '%.storedata')
ORDER BY domain, relativePath;
```

**Resolve a known artifact → on-disk blob name** (forward-hash; exact path is fastest, `LIKE` when unsure) — [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]], [[04-logical-acquisition-with-libimobiledevice]], [[05-backup-restore-migration-and-transfer]]
```sql
-- exact:
SELECT fileID, domain, relativePath FROM Files WHERE relativePath = 'Library/SMS/sms.db';
-- fuzzy / several artifacts at once:
SELECT fileID, domain, relativePath, flags FROM Files
WHERE relativePath LIKE '%sms.db' OR relativePath LIKE '%Photos.sqlite'
   OR relativePath LIKE '%CallHistory%'
ORDER BY domain;
```

**Locate CommCenter (cellular-identity) plists** in a backup — [[04-baseband-and-cellular]]
```sql
SELECT fileID, relativePath FROM Files WHERE relativePath LIKE '%commcenter%';
```

**Locate WhatsApp's real DB in an app-group domain** — [[00-app-sandbox-and-filesystem-layout]]
```sql
SELECT domain, relativePath, fileID FROM Files
WHERE relativePath LIKE '%sms.db'
   OR (domain LIKE 'AppDomainGroup-%' AND relativePath LIKE '%ChatStorage.sqlite');
```

**Locate notification / keyboard / accounts stores** (HomeDomain) — [[13-notifications-keyboard-and-misc-stores]]
```sql
SELECT fileID, relativePath FROM Files
WHERE domain='HomeDomain'
  AND (relativePath LIKE 'Library/UserNotifications/%'
    OR relativePath LIKE 'Library/Keyboard/%'
    OR relativePath = 'Library/Accounts/Accounts3.sqlite');
```

**Peek file map + protection flags** (quick sanity look) — [[00-ios-forensics-landscape-and-authorization]]
```sql
SELECT domain, relativePath, flags FROM Files LIMIT 20;
```

**Extract a row's `MBFile` metadata blob** (NSKeyedArchiver bplist: Mode/UID/GID/MTime/CTime/BTime/Size/InodeNumber + `ProtectionClass` + wrapped `EncryptionKey`) — [[10-device-services-and-backups]], [[03-the-itunes-finder-backup-format]]
```sql
SELECT writefile('/tmp/mbfile.bplist', file) FROM Files
WHERE fileID='3d0d7e5fb2ce288813306e4d4636395e047a3d28';
-- then: plutil -p /tmp/mbfile.bplist
```

---

## Communications

### `sms.db` (iMessage / SMS) — [[04-communications-imessage-and-sms]], [[14-deleted-data-recovery]]

> **Path:** `/private/var/mobile/Library/SMS/sms.db` (+ `Attachments/`), `HomeDomain` in a backup. Identical
> schema to macOS `chat.db`. **Copy first** — message recovery depends on the `-wal`. **Epoch:** Mac-Absolute
> **nanoseconds** on iOS 11+ (`/1000000000 + 978307200`); older rows are seconds. Bodies are sometimes only
> in the `attributedBody` BLOB, not `text`.

**Confirm a resolved blob really is the SMS DB** — [[03-the-itunes-finder-backup-format]]
```sql
SELECT name FROM sqlite_master WHERE type='table';
```

**Magnitude-aware epoch convert** (handles ns-or-seconds rows in one expression) — [[04-communications-imessage-and-sms]]
```sql
SELECT datetime(CASE WHEN message.date > 1000000000000
                     THEN message.date / 1000000000
                     ELSE message.date END + 978307200,
                'unixepoch', 'localtime') AS sent
FROM message;
```

**Full conversation reconstruction** (sender / direction / body / read receipt) — [[04-communications-imessage-and-sms]]
```sql
SELECT datetime(m.date/1000000000 + 978307200,'unixepoch','localtime') AS sent,
       c.chat_identifier,
       CASE m.is_from_me WHEN 1 THEN 'ME' ELSE h.id END AS who,
       m.service,
       COALESCE(m.text,'[body in attributedBody]') AS body,
       CASE WHEN m.date_read>0
            THEN datetime(m.date_read/1000000000+978307200,'unixepoch','localtime') END AS read_at
FROM message m
JOIN chat_message_join cmj ON m.ROWID=cmj.message_id
JOIN chat c ON cmj.chat_id=c.ROWID
LEFT JOIN handle h ON m.handle_id=h.ROWID
ORDER BY m.date LIMIT 40;
```

**Resolve tapbacks/reactions to their parent message** (`associated_message_type` 2000–3007) — [[04-communications-imessage-and-sms]]
```sql
SELECT datetime(r.date/1000000000+978307200,'unixepoch','localtime') AS t,
       CASE r.is_from_me WHEN 1 THEN 'ME' ELSE h.id END AS who,
       r.associated_message_type,
       COALESCE(t.text,'[parent body in attributedBody]') AS parent_body
FROM message r
LEFT JOIN handle h ON r.handle_id=h.ROWID
LEFT JOIN message t ON t.guid = replace(replace(r.associated_message_guid,'p:0/',''),'bp:','')
WHERE r.associated_message_type BETWEEN 2000 AND 3007
ORDER BY r.date DESC LIMIT 30;
```

**Group-chat roster + display name** (`style = 43` = group) — [[04-communications-imessage-and-sms]]
```sql
SELECT c.ROWID, c.display_name, c.chat_identifier, h.id AS participant
FROM chat c
JOIN chat_handle_join chj ON c.ROWID=chj.chat_id
JOIN handle h ON chj.handle_id=h.ROWID
WHERE c.style = 43
ORDER BY c.ROWID, h.id;
```

**Attachments for a thread** — [[04-communications-imessage-and-sms]]
```sql
SELECT m.ROWID, a.mime_type, a.total_bytes, a.transfer_name, a.filename
FROM message m
JOIN message_attachment_join maj ON m.ROWID=maj.message_id
JOIN attachment a ON maj.attachment_id=a.ROWID
ORDER BY a.created_date DESC LIMIT 20;
```

**Attachment MIME-type census** (e.g. Lockdown-Mode negative-space analysis) — [[06-lockdown-mode-and-enterprise-posture]]
```sql
SELECT mime_type, COUNT(*) FROM attachment GROUP BY mime_type ORDER BY 2 DESC;
```

**Recover original text of an edited / unsent message** (parse the BLOB) — [[04-communications-imessage-and-sms]]
```sql
SELECT writefile('/tmp/msi.plist', message_summary_info)
FROM message WHERE date_edited > 0 LIMIT 1;
-- then: plutil -p /tmp/msi.plist
```

**Recover Recently-Deleted messages** (still linked via the recoverable join, ~30-day window) — [[14-deleted-data-recovery]]
```sql
SELECT m.ROWID, datetime(m.date/1000000000 + 978307200,'unixepoch','localtime') AS sent,
       h.id, m.text
FROM chat_recoverable_message_join crmj
JOIN message m ON m.ROWID=crmj.message_id
LEFT JOIN handle h ON h.ROWID=m.handle_id
ORDER BY m.date DESC;
```

**Future-dated row sweep** (clock-tamper / back-dating tell) — [[02-correlation-and-anti-forensics]]
```sql
SELECT ROWID, datetime(date/1000000000+978307200,'unixepoch') AS msg_utc, text
FROM message
WHERE date/1000000000+978307200 > <acquisition_epoch>;
```

### `CallHistory.storedata` (call log) — [[05-call-history-voicemail-contacts-interactions]]

> **Path:** `/private/var/mobile/Library/CallHistoryDB/CallHistory.storedata` (Core Data). **Copy first.**
> **Epoch:** Mac-Absolute seconds (`+978307200`). `ZADDRESS` is a BLOB — `CAST(... AS TEXT)`.
> `ZCALLTYPE`: 1 = cellular/standard, 8 = FaceTime-video, 16 = FaceTime-audio. `ZORIGINATED`: 0 = in, 1 = out.

**Call log with direction / answered / type / provider** — [[05-call-history-voicemail-contacts-interactions]]
```sql
SELECT datetime(ZDATE + 978307200,'unixepoch','localtime') AS t,
       CAST(ZADDRESS AS TEXT) AS number,
       CASE ZORIGINATED WHEN 0 THEN 'IN' WHEN 1 THEN 'OUT' END AS dir,
       CASE ZANSWERED WHEN 1 THEN 'answered' ELSE 'missed' END AS answered,
       CASE ZCALLTYPE WHEN 1 THEN 'cellular/std' WHEN 8 THEN 'FT-video'
                      WHEN 16 THEN 'FT-audio' ELSE ZCALLTYPE END AS call_type,
       ZSERVICE_PROVIDER, CAST(ZDURATION AS INT) AS secs
FROM ZCALLRECORD ORDER BY ZDATE DESC LIMIT 25;
```

### `voicemail.db` (visual voicemail) — [[05-call-history-voicemail-contacts-interactions]]

> **Path:** `/private/var/mobile/Library/Voicemail/voicemail.db`. **Copy first.** **Two-epoch trap:**
> `date` and `expiration` are **plain Unix seconds**; `trashed_date` in the *same table* is **Mac-Absolute**
> (`+978307200`).

**Voicemails, both epochs read correctly** — [[05-call-history-voicemail-contacts-interactions]]
```sql
SELECT ROWID,
       datetime(date,'unixepoch','localtime') AS received,
       sender, callback_num, duration,
       CASE WHEN trashed_date>0 THEN datetime(trashed_date+978307200,'unixepoch') END AS trashed,
       flags
FROM voicemail ORDER BY date DESC LIMIT 25;
```

### `AddressBook.sqlitedb` (contacts) — [[05-call-history-voicemail-contacts-interactions]]

> **Path:** `/private/var/mobile/Library/AddressBook/AddressBook.sqlitedb`. **Copy first.** **Epoch:**
> Mac-Absolute seconds (`+978307200`) for `CreationDate`/`ModificationDate`/`Birthday`. Phone/email values
> live in the `ABMultiValue` side table, labelled via `ABMultiValueLabel`.

**Three-table contact join** (name / label / value / dates) — [[05-call-history-voicemail-contacts-interactions]]
```sql
SELECT p.ROWID, p.First || ' ' || IFNULL(p.Last,'') AS name,
       l.value AS label, v.value AS value,
       datetime(p.CreationDate+978307200,'unixepoch') AS created,
       datetime(p.ModificationDate+978307200,'unixepoch') AS modified
FROM ABPerson p
JOIN ABMultiValue v ON v.record_id=p.ROWID
LEFT JOIN ABMultiValueLabel l ON l.ROWID=v.label
ORDER BY p.ModificationDate DESC LIMIT 40;
```

### `interactionC.db` (CoreDuet interactions / contact graph) — [[05-call-history-voicemail-contacts-interactions]]

> **Path:** pattern-of-life store under CoreDuet. **Copy first.** **Epoch:** Mac-Absolute seconds
> (`+978307200`) on all `Z*DATE`. Captures cross-app comms including WhatsApp/Signal (`ZBUNDLEID`).

**Rank correspondents by volume + recency** — [[05-call-history-voicemail-contacts-interactions]]
```sql
SELECT ZDISPLAYNAME, ZIDENTIFIER,
       ZINCOMINGSENDERCOUNT, ZOUTGOINGRECIPIENTCOUNT,
       (ZINCOMINGSENDERCOUNT + ZOUTGOINGRECIPIENTCOUNT) AS total,
       datetime(ZFIRSTINCOMINGSENDERDATE+978307200,'unixepoch') AS first,
       datetime(ZLASTINCOMINGSENDERDATE+978307200,'unixepoch') AS last
FROM ZCONTACTS ORDER BY total DESC LIMIT 20;
```

**Per-app interaction breakdown** (catches third-party messengers) — [[05-call-history-voicemail-contacts-interactions]]
```sql
SELECT ZBUNDLEID, COUNT(*) AS n,
       SUM(ZDIRECTION=0) AS incoming, SUM(ZDIRECTION=1) AS outgoing
FROM ZINTERACTIONS GROUP BY ZBUNDLEID ORDER BY n DESC;
```

---

## Pattern of life

### `knowledgeC.db` (CoreDuet "knowledge" store) — [[01-knowledgec-db-deep-dive]], [[04-launchd-and-system-daemons]], [[05-full-file-system-acquisition]], [[02-biome-and-segb-streams]], [[02-correlation-and-anti-forensics]]

> **Path:** `/private/var/mobile/Library/CoreDuet/Knowledge/knowledgeC.db`. **Device-only — absent on the
> Simulator.** **Copy first.** **Epoch:** Mac-Absolute **seconds** on `ZSTARTDATE`/`ZENDDATE` (`+978307200`);
> `ZSECONDSFROMGMT` is the per-row device UTC offset (add it for device-local; a discontinuity = travel or a
> clock change). The richest single pattern-of-life store; superseded but not replaced by Biome/SEGB at iOS 17.

**Stream census** (which streams exist, counts, date range) — [[01-knowledgec-db-deep-dive]], [[05-full-file-system-acquisition]]
```sql
SELECT ZSTREAMNAME, COUNT(*) AS n,
       datetime(MIN(ZSTARTDATE)+978307200,'unixepoch') AS first_utc,
       datetime(MAX(ZSTARTDATE)+978307200,'unixepoch') AS last_utc
FROM ZOBJECT GROUP BY ZSTREAMNAME ORDER BY n DESC;
```

**App-in-focus timeline** with duration + tz offset — [[01-knowledgec-db-deep-dive]], [[04-launchd-and-system-daemons]]
```sql
SELECT datetime(ZSTARTDATE+978307200,'unixepoch') AS start_utc,
       datetime(ZENDDATE+978307200,'unixepoch')   AS end_utc,
       CAST(ZENDDATE-ZSTARTDATE AS INTEGER)        AS secs,
       ZVALUESTRING                                AS bundle_id,
       printf('%+d',ZSECONDSFROMGMT/3600)          AS tz
FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'
ORDER BY ZSTARTDATE DESC LIMIT 40;
```

**Device-state presence triad** (locked / backlit on-off) — [[01-knowledgec-db-deep-dive]]
```sql
SELECT datetime(ZSTARTDATE+978307200,'unixepoch') AS t,
       ZSTREAMNAME,
       CASE ZVALUEINTEGER WHEN 1 THEN 'ON/LOCKED' ELSE 'OFF/UNLOCKED' END AS state
FROM ZOBJECT WHERE ZSTREAMNAME IN ('/device/isLocked','/display/isBacklit')
ORDER BY ZSTARTDATE DESC LIMIT 60;
```

**Presence window across multiple streams within a time box** (correlation) — [[02-correlation-and-anti-forensics]]
```sql
SELECT ZSTREAMNAME, ZVALUESTRING AS app,
       datetime(ZSTARTDATE+978307200,'unixepoch') AS start_utc,
       datetime(ZENDDATE+978307200,'unixepoch')   AS end_utc,
       CAST(ZENDDATE-ZSTARTDATE AS INT) AS secs
FROM ZOBJECT
WHERE ZSTREAMNAME IN ('/app/inFocus','/display/isBacklit','/device/locked')
  AND ZSTARTDATE+978307200 BETWEEN strftime('%s','2026-06-20 13:00')
                               AND strftime('%s','2026-06-20 16:00')
ORDER BY ZSTARTDATE;
```

**App-install history** (survives MobileInstallation log loss) — [[01-knowledgec-db-deep-dive]]
```sql
SELECT datetime(ZSTARTDATE+978307200,'unixepoch') AS installed_utc,
       ZVALUESTRING AS bundle_id
FROM ZOBJECT WHERE ZSTREAMNAME='/app/install' ORDER BY ZSTARTDATE;
```

**Total foreground time per app** — [[01-knowledgec-db-deep-dive]]
```sql
SELECT ZVALUESTRING, COUNT(*) AS sessions,
       printf('%.1f', SUM(ZENDDATE-ZSTARTDATE)/60.0) AS total_minutes
FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'
GROUP BY ZVALUESTRING ORDER BY SUM(ZENDDATE-ZSTARTDATE) DESC LIMIT 25;
```

**Per-local-hour activity histogram** (sleep/work rhythm) — [[01-knowledgec-db-deep-dive]]
```sql
SELECT strftime('%H', ZSTARTDATE+978307200+ZSECONDSFROMGMT,'unixepoch') AS hour_local,
       COUNT(*), printf('%.0f', SUM(ZENDDATE-ZSTARTDATE)/60.0) AS minutes
FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'
GROUP BY hour_local ORDER BY hour_local;
```

**Intents metadata join** (source app + payload) — [[01-knowledgec-db-deep-dive]]
```sql
SELECT datetime(o.ZSTARTDATE+978307200,'unixepoch') AS t, s.ZBUNDLEID, o.ZVALUESTRING
FROM ZOBJECT o LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
WHERE o.ZSTREAMNAME='/app/intents' ORDER BY o.ZSTARTDATE DESC LIMIT 30;
```

**Detect timezone changes** (travel / clock tamper) — [[01-knowledgec-db-deep-dive]]
```sql
SELECT DISTINCT ZSECONDSFROMGMT FROM ZOBJECT;
```

**Insertion-order vs timestamp sanity** (back-dating check) — [[01-knowledgec-db-deep-dive]]
```sql
SELECT Z_PK, datetime(ZSTARTDATE+978307200,'unixepoch') FROM ZOBJECT ORDER BY Z_PK DESC LIMIT 50;
```

**APOLLO-style minimal inFocus** (cross-corroborate Biome twin / portable form) — [[01-knowledgec-db-deep-dive]], [[02-biome-and-segb-streams]]
```sql
SELECT DATETIME(ZSTARTDATE + 978307200,'UNIXEPOCH') AS "START",
       DATETIME(ZENDDATE   + 978307200,'UNIXEPOCH') AS "END",
       ZVALUESTRING AS "BUNDLE ID"
FROM ZOBJECT WHERE ZSTREAMNAME = '/app/inFocus';
```

### `CurrentPowerlog.PLSQL` (PowerLog) — [[03-powerlog-and-aggregate-dictionary]], [[07-connectivity-power-sensors-dfu]], [[02-correlation-and-anti-forensics]]

> **Path:** `/private/var/containers/Shared/SystemGroup/<GUID>/Library/BatteryLife/CurrentPowerlog.PLSQL`
> (older windows in sibling `Archives/`), ~7-day rolling window. **Device-only.** **Copy first.** **Epoch:**
> raw `TIMESTAMP` is **Unix seconds** but on a *monotonic* timebase — the true wall-clock is
> `TIMESTAMP + SYSTEM`, where `SYSTEM` is the offset in effect at that event, taken from
> `PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET`. Use `APOLLO` to normalize table/column drift across iOS versions.

**Battery level / charge timeline** (simple, uncorrected) — [[07-connectivity-power-sensors-dfu]]
```sql
SELECT datetime(timestamp,'unixepoch','localtime') AS t, Level, IsCharging
FROM PLBatteryAgent_EventBackward_Battery ORDER BY timestamp DESC LIMIT 20;
```

**Display / backlight on-off + brightness** (timeline anchoring) — [[07-connectivity-power-sensors-dfu]]
```sql
SELECT datetime(timestamp,'unixepoch','localtime') AS t, *
FROM PLDisplayAgent_EventForward_Display ORDER BY timestamp DESC LIMIT 20;
```

**Lock-state timeline with per-event offset correction** — [[03-powerlog-and-aggregate-dictionary]]
```sql
SELECT datetime(b.TIMESTAMP + o.SYSTEM,'unixepoch') AS adjusted_utc,
       CASE b.LOCKED WHEN 0 THEN 'UNLOCKED' WHEN 1 THEN 'LOCKED' END AS state,
       datetime(b.TIMESTAMP,'unixepoch') AS raw, o.SYSTEM AS offset
FROM PLSPRINGBOARDAGENT_EVENTFORWARD_SBLOCK b
LEFT JOIN PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET o
  ON o.ID = (SELECT MAX(ID) FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
             WHERE TIMESTAMP <= b.TIMESTAMP)
ORDER BY b.TIMESTAMP DESC LIMIT 40;
```

**Foreground-app + screen-on timeline** (energy-side inFocus) — [[03-powerlog-and-aggregate-dictionary]]
```sql
SELECT datetime(s.TIMESTAMP + o.SYSTEM,'unixepoch') AS t,
       s.BUNDLEID, s.APPROLE, s.DISPLAY, s.LEVEL
FROM PLSCREENSTATEAGENT_EVENTFORWARD_SCREENSTATE s
LEFT JOIN PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET o
  ON o.ID = (SELECT MAX(ID) FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
             WHERE TIMESTAMP <= s.TIMESTAMP)
WHERE s.BUNDLEID IS NOT NULL ORDER BY s.TIMESTAMP DESC LIMIT 40;
```

**Which apps used location, when** — [[03-powerlog-and-aggregate-dictionary]]
```sql
SELECT datetime(l.TIMESTAMP + o.SYSTEM,'unixepoch') AS t,
       l.BUNDLEID, l.CLIENT, l.TYPE, l.LOCATIONDESIREDACCURACY
FROM PLLOCATIONAGENT_EVENTFORWARD_CLIENTSTATUS l
LEFT JOIN PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET o
  ON o.ID = (SELECT MAX(ID) FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET
             WHERE TIMESTAMP <= l.TIMESTAMP)
ORDER BY l.TIMESTAMP DESC LIMIT 30;
```

**Clock-change ledger** (detect manual time jumps via offset deltas) — [[03-powerlog-and-aggregate-dictionary]], [[02-correlation-and-anti-forensics]]
```sql
SELECT ID, datetime(TIMESTAMP,'unixepoch') AS row_wallclock,
       SYSTEM AS offset_secs,
       SYSTEM - LAG(SYSTEM) OVER (ORDER BY ID) AS delta_vs_prev
FROM PLSTORAGEOPERATOR_EVENTFORWARD_TIMEOFFSET ORDER BY ID;
```

### `ADDataStore.sqlitedb` (Aggregate Dictionary) — [[03-powerlog-and-aggregate-dictionary]]

> **Path:** Aggregate Dictionary store. **Copy first.** **Epoch:** day-bucket — `DAYSSINCE1970 * 86400` then
> `'unixepoch'`. Keeps per-UTC-day counters, useful when finer logs have rolled off.

**Per-UTC-day authentication counters** (passcode entered / failed / type) — [[03-powerlog-and-aggregate-dictionary]]
```sql
SELECT DATE(DAYSSINCE1970*86400,'unixepoch') AS day, KEY, VALUE
FROM SCALARS
WHERE KEY IN ('com.apple.passcode.NumPasscodeEntered',
              'com.apple.passcode.NumPasscodeFailed',
              'com.apple.passcode.PasscodeType')
ORDER BY day DESC, KEY;
```

> **Biome / SEGB note:** the iOS-17+ pattern-of-life successor (`/private/var/mobile/Library/Biome/streams/{public,restricted}/`)
> is **SEGB protobuf streams, not SQLite** — parse with `ccl-segb` or APOLLO, not `sqlite3`. Timestamps are
> Cocoa/Mac-Absolute float64 (`+978307200`). Cross-corroborate `App.InFocus` against the knowledgeC twin above. See [[02-biome-and-segb-streams]].

---

## Location

> All routined/locationd stores live under `/private/var/mobile/Library/Caches/com.apple.routined/` (or
> `/private/var/root/Library/Caches/locationd/`). **Device-only, copy first.** **Epoch:** Mac-Absolute
> seconds (`+978307200`) throughout. Filter the `-180.0` / invalid-speed sentinels.

### `Cache.sqlite` (routined — significant-location witnesses) — [[07-location-history]], [[02-correlation-and-anti-forensics]]

**Speed-aware fix track** (drops invalid speed, derives mph/kmh) — [[07-location-history]]
```sql
SELECT datetime(ZTIMESTAMP+978307200,'unixepoch') AS t,
       ZLATITUDE, ZLONGITUDE, ZALTITUDE, ZSPEED,
       round(ZSPEED*2.23694,1) AS mph, round(ZSPEED*3.6,1) AS kmh,
       ZCOURSE, ZHORIZONTALACCURACY, ZVERTICALACCURACY, Z_PK
FROM ZRTCLLOCATIONMO WHERE ZSPEED >= 0 ORDER BY ZTIMESTAMP;
```

**Plain significant-location witness** (lat/long/accuracy) — [[02-correlation-and-anti-forensics]]
```sql
SELECT datetime(ZTIMESTAMP+978307200,'unixepoch') AS t_utc,
       ZLATITUDE, ZLONGITUDE, ZHORIZONTALACCURACY
FROM ZRTCLLOCATIONMO ORDER BY ZTIMESTAMP;
```

**Core Data entity catalog** (orientation for any routined store) — [[07-location-history]]
```sql
SELECT Z_NAME, Z_ENT, Z_SUPER FROM Z_PRIMARYKEY ORDER BY Z_NAME;
```

### `Local.sqlite` / `Cloud-V2.sqlite` (routined — learned visits & LOIs) — [[07-location-history]]

**Significant-Locations dwell visits** (entry/exit) — [[07-location-history]]
```sql
SELECT datetime(ZENTRYDATE+978307200,'unixepoch') AS entry,
       datetime(ZEXITDATE+978307200,'unixepoch')  AS exit,
       datetime(ZCREATIONDATE+978307200,'unixepoch') AS created,
       ZLATITUDE, ZLONGITUDE
FROM ZRTLEARNEDVISITMO ORDER BY ZENTRYDATE DESC;
```

**Name Locations-of-Interest via the linked map item** — [[07-location-history]]
```sql
SELECT loi.Z_PK, loi.ZLATITUDE, loi.ZLONGITUDE, mi.ZNAME,
       datetime(loi.ZCREATIONDATE+978307200,'unixepoch') AS created
FROM ZRTLEARNEDLOCATIONOFINTERESTMO loi
LEFT JOIN ZRTMAPITEMMO mi ON mi.Z_PK = loi.ZMAPITEM
ORDER BY loi.ZCREATIONDATE;
```

**Parked-vehicle events** — [[07-location-history]]
```sql
SELECT datetime(ZDATE+978307200,'unixepoch') AS t, ZLATITUDE, ZLONGITUDE
FROM ZRTLEARNEDVEHICLELOCATIONMO ORDER BY ZDATE DESC;
```

### `cache_encryptedB.db` (locationd — own observed APs) — [[07-location-history]]

> Also the cell-observation cache reported by the modem ([[04-baseband-and-cellular]]). Mac-Absolute seconds.

**Device's own observed Wi-Fi APs** (BSSID + coords) — [[07-location-history]]
```sql
SELECT datetime(Timestamp + 978307200,'unixepoch') AS t,
       MAC, Latitude, Longitude, HorizontalAccuracy
FROM WifiLocationHarvest ORDER BY Timestamp DESC;
```

### `MapsSync_0.0.1` (Apple Maps) — [[07-location-history]]

**History items carrying a route protobuf** (then decode the BLOB) — [[07-location-history]]
```sql
SELECT Z_PK, length(ZROUTEREQUESTSTORAGE)
FROM ZHISTORYITEM WHERE ZROUTEREQUESTSTORAGE NOT NULL;
```

---

## Media — `Photos.sqlite` — [[06-photos-and-the-camera-roll]], [[03-trackpad-keyboard-and-apple-pencil]], [[14-deleted-data-recovery]]

> **Path:** `/private/var/mobile/Media/PhotoData/Photos.sqlite`, `CameraRollDomain` in a backup, AFC-reachable
> on an AFU device. **Copy first.** **Epoch:** Mac-Absolute seconds (`+978307200`) on
> `ZDATECREATED`/`ZADDEDDATE`/`ZMODIFICATIONDATE`/`ZTRASHEDDATE`; `ZEXIFTIMESTAMPSTRING` is plain wall-clock
> text. Filter the `-180.0` no-fix sentinel on coordinates. The asset↔album join table is version-numbered
> (`Z_<N>ASSETS`) — discover its name first.

**Core asset who / where / when / how** (the workhorse join) — [[06-photos-and-the-camera-roll]]
```sql
SELECT a.Z_PK, a.ZFILENAME, a.ZDIRECTORY,
       datetime(a.ZDATECREATED+978307200,'unixepoch','localtime') AS created,
       datetime(a.ZADDEDDATE+978307200,'unixepoch','localtime')   AS added,
       a.ZLATITUDE, a.ZLONGITUDE, a.ZKIND, a.ZSAVEDASSETTYPE, a.ZTRASHEDSTATE,
       aa.ZORIGINALFILENAME, aa.ZEXIFTIMESTAMPSTRING, aa.ZTIMEZONENAME,
       aa.ZIMPORTEDBYBUNDLEIDENTIFIER
FROM ZASSET a
LEFT JOIN ZADDITIONALASSETATTRIBUTES aa ON aa.ZASSET=a.Z_PK
ORDER BY a.ZDATECREATED DESC LIMIT 25;
```

**Recently-Deleted assets + projected purge date** (`ZTRASHEDSTATE=1`, +30 days) — [[06-photos-and-the-camera-roll]], [[14-deleted-data-recovery]]
```sql
SELECT ZUUID, ZFILENAME,
       datetime(ZTRASHEDDATE+978307200,'unixepoch','localtime') AS trashed,
       date(ZTRASHEDDATE+978307200+30*86400,'unixepoch','localtime') AS purges_on
FROM ZASSET WHERE ZTRASHEDSTATE=1 ORDER BY ZTRASHEDDATE DESC;
```

**Named persons + faces count** — [[06-photos-and-the-camera-roll]]
```sql
SELECT p.ZDISPLAYNAME, p.ZFACECOUNT, COUNT(f.Z_PK)
FROM ZPERSON p LEFT JOIN ZDETECTEDFACE f ON f.ZPERSONFORFACE=p.Z_PK
GROUP BY p.Z_PK ORDER BY p.ZFACECOUNT DESC;
```

**Geotagged assets** (filter the `-180.0` no-fix sentinel) — [[06-photos-and-the-camera-roll]]
```sql
SELECT ZFILENAME, datetime(ZDATECREATED+978307200,'unixepoch','localtime') AS created,
       printf('%.6f, %.6f', ZLATITUDE, ZLONGITUDE) AS coords
FROM ZASSET WHERE ZLATITUDE != -180.0 AND ZLONGITUDE != -180.0 ORDER BY ZDATECREATED;
```

**Attribution breakdown** (how each photo arrived: camera vs imported-by-app) — [[06-photos-and-the-camera-roll]]
```sql
SELECT aa.ZIMPORTEDBYBUNDLEIDENTIFIER AS saved_by, a.ZSAVEDASSETTYPE AS saved_type, COUNT(*) AS n
FROM ZASSET a LEFT JOIN ZADDITIONALASSETATTRIBUTES aa ON aa.ZASSET=a.Z_PK
GROUP BY saved_by, saved_type ORDER BY n DESC;
```

**Candidate screenshot PNG assets** — [[03-trackpad-keyboard-and-apple-pencil]]
```sql
SELECT Z_PK, ZFILENAME, datetime(ZDATECREATED + 978307200,'unixepoch','localtime') AS created
FROM ZASSET WHERE ZFILENAME LIKE '%.PNG' OR ZFILENAME LIKE 'IMG%.PNG'
ORDER BY ZDATECREATED DESC LIMIT 30;
```

**Discover the version-numbered album join table** — [[06-photos-and-the-camera-roll]]
```sql
SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z_%ASSETS';
```

---

## Browsers

### `History.db` (Safari) — [[08-safari-and-third-party-browsers]], [[01-simulator-internals-and-on-disk-filesystem]]

> **Path:** `/private/var/mobile/Library/Safari/History.db`. **Copy first.** **Epoch:** Mac-Absolute seconds
> (`+978307200`) on `visit_time`. (`Cookies.binarycookies` creation/expiration doubles are the same epoch.)

**History timeline** (visits joined to items) — [[08-safari-and-third-party-browsers]], [[01-simulator-internals-and-on-disk-filesystem]]
```sql
SELECT datetime(v.visit_time + 978307200,'unixepoch','localtime') AS t,
       i.url, v.title, i.visit_count, v.load_successful
FROM history_visits v JOIN history_items i ON v.history_item=i.id
ORDER BY v.visit_time DESC LIMIT 50;
```

**Pull search terms out of URLs** — [[08-safari-and-third-party-browsers]]
```sql
SELECT datetime(v.visit_time + 978307200,'unixepoch','localtime') AS t, i.url
FROM history_visits v JOIN history_items i ON v.history_item=i.id
WHERE i.url LIKE '%q=%' OR i.url LIKE '%search%'
ORDER BY v.visit_time DESC LIMIT 40;
```

### `CloudTabs.db` / `SafariTabs.db` (Safari iCloud tabs) — [[08-safari-and-third-party-browsers]]

**Enumerate the iCloud device fleet** (`CloudTabs.db`) — [[08-safari-and-third-party-browsers]]
```sql
SELECT device_name, device_uuid FROM cloud_tab_devices;
```

**Export a tab's `local_attributes` BLOB** (`SafariTabs.db`) — [[08-safari-and-third-party-browsers]]
```sql
SELECT writefile('/tmp/tab0.bin', local_attributes) FROM bookmarks LIMIT 1;
```

### Chrome `History` (iOS) — [[08-safari-and-third-party-browsers]], [[00-the-ios-timestamp-zoo]]

> **Epoch:** WebKit/Chrome — microseconds since **1601** → `/1000000 − 11644473600`.

**History with the 1601 µs epoch** — [[08-safari-and-third-party-browsers]]
```sql
SELECT datetime(last_visit_time/1000000 - 11644473600,'unixepoch','localtime') AS t,
       url, title, visit_count
FROM urls ORDER BY last_visit_time DESC LIMIT 30;
```

### Firefox `moz_historyvisits` / `moz_places` (iOS) — [[00-the-ios-timestamp-zoo]]

> **Epoch:** PRTime — microseconds since **1970** → `/1000000` (no offset).

**History with PRTime µs epoch** — [[00-the-ios-timestamp-zoo]]
```sql
SELECT datetime(visit_date/1000000, 'unixepoch') FROM moz_historyvisits;
```

---

## Notes, Mail, Calendar, Reminders

### `NoteStore.sqlite` (Apple Notes) — [[09-mail-notes-calendar-reminders]], [[00-how-ipados-diverges-from-ios]], [[03-trackpad-keyboard-and-apple-pencil]], [[14-deleted-data-recovery]]

> **Path:** app-group container (`Notes` group). **Copy first.** **Epoch:** Mac-Absolute seconds
> (`+978307200`) on `ZCREATIONDATE1`/`ZMODIFICATIONDATE1`. Note bodies are **gzipped** in `ZICNOTEDATA.ZDATA` —
> export then `gunzip`. `ZMARKEDFORDELETION=1` = soft-deleted (Plane-1 read).

**Triage notes** (title / snippet / dates / flags / account) — [[09-mail-notes-calendar-reminders]]
```sql
SELECT obj.Z_PK, obj.ZTITLE1, obj.ZSNIPPET,
       datetime(obj.ZCREATIONDATE1+978307200,'unixepoch','localtime') AS created,
       datetime(obj.ZMODIFICATIONDATE1+978307200,'unixepoch','localtime') AS modified,
       obj.ZMARKEDFORDELETION, obj.ZISPASSWORDPROTECTED
FROM ZICCLOUDSYNCINGOBJECT obj
WHERE obj.ZNOTEDATA IS NOT NULL
ORDER BY obj.ZMODIFICATIONDATE1 DESC;
```

**List notes created vs modified** (flag post-drawing edits / find embedded drawings) — [[00-how-ipados-diverges-from-ios]], [[03-trackpad-keyboard-and-apple-pencil]]
```sql
SELECT Z_PK, ZTITLE1,
       datetime(ZCREATIONDATE1 + 978307200,'unixepoch','localtime') AS created,
       datetime(ZMODIFICATIONDATE1 + 978307200,'unixepoch','localtime') AS modified
FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE1 IS NOT NULL
ORDER BY ZMODIFICATIONDATE1 DESC LIMIT 20;
```

**Export a note's gzipped body** — [[09-mail-notes-calendar-reminders]]
```sql
SELECT writefile('/tmp/notes/note.gz', ZDATA) FROM ZICNOTEDATA WHERE Z_PK = 12;
-- then: gunzip /tmp/notes/note.gz
```

**Flagged-for-deletion notes** (Plane-1 read) — [[14-deleted-data-recovery]]
```sql
SELECT Z_PK, ZTITLE1, ZMARKEDFORDELETION
FROM ZICCLOUDSYNCINGOBJECT WHERE ZMARKEDFORDELETION = 1;
```

### Mail — `Envelope Index` + `Protected Index` — [[09-mail-notes-calendar-reminders]]

> **Path:** `/private/var/mobile/Library/Mail/`. **Copy first.** **Epoch:** Mail is the exception — `date_*`
> columns are **plain Unix seconds** (`'unixepoch'`, NO `+978307200`). Subjects/summaries live in the separate
> `Protected Index`.

**Messages with dates + mailbox** (`Envelope Index`) — [[09-mail-notes-calendar-reminders]]
```sql
SELECT m.ROWID, datetime(m.date_received,'unixepoch','localtime') AS received, mb.url
FROM messages m LEFT JOIN mailboxes mb ON m.mailbox = mb.ROWID
ORDER BY m.date_received DESC LIMIT 40;
```

**Subjects + ~500-byte summaries** (`Protected Index`) — [[09-mail-notes-calendar-reminders]]
```sql
SELECT s.subject, sum.summary
FROM Subjects s LEFT JOIN Summaries sum ON s.message_id = sum.message_id LIMIT 40;
```

### `Calendar.sqlitedb` — [[09-mail-notes-calendar-reminders]]

> **Copy first.** **Epoch:** Mac-Absolute seconds (`+978307200`) on `start_date`/`end_date` (stored UTC with a
> separate tz column).

**Events with place + calendar + account** — [[09-mail-notes-calendar-reminders]]
```sql
SELECT ci.summary,
       datetime(ci.start_date+978307200,'unixepoch','localtime') AS start,
       datetime(ci.end_date+978307200,'unixepoch','localtime')   AS end,
       loc.title AS place, cal.title AS calendar, st.name AS account
FROM CalendarItem ci
LEFT JOIN Location loc ON ci.location_id=loc.ROWID
LEFT JOIN Calendar cal ON ci.calendar_id=cal.ROWID
LEFT JOIN Store st ON cal.store_id=st.ROWID
ORDER BY ci.start_date DESC LIMIT 40;
```

**Attendees for an event** — [[09-mail-notes-calendar-reminders]]
```sql
SELECT id.display_name, id.address, p.status, p.role
FROM Participant p JOIN Identity id ON p.identity_id=id.ROWID
WHERE p.owner_id = 17;
```

### Reminders — `Data-<UUID>.sqlite` — [[09-mail-notes-calendar-reminders]]

> **Copy first.** **Epoch:** Mac-Absolute seconds (`+978307200`).

**Open + completed reminders** — [[09-mail-notes-calendar-reminders]]
```sql
SELECT ZTITLE1,
       datetime(ZCREATIONDATE+978307200,'unixepoch','localtime')   AS created,
       datetime(ZDUEDATE+978307200,'unixepoch','localtime')        AS due,
       datetime(ZCOMPLETIONDATE+978307200,'unixepoch','localtime') AS completed,
       ZFLAGGED
FROM ZREMCDOBJECT WHERE ZTITLE1 IS NOT NULL ORDER BY ZCREATIONDATE DESC;
```

**Core Data entity demux** (run before querying any Notes/Reminders store) — [[09-mail-notes-calendar-reminders]]
```sql
SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY ORDER BY Z_ENT;
```

---

## Health — `healthdb_secure.sqlite` — [[10-health-and-fitness]], [[07-connectivity-power-sensors-dfu]]

> **Path:** `/private/var/mobile/Library/Health/healthdb_secure.sqlite`. The most sensitive store;
> `HealthDomain` is **encrypted-backup-only** (absent from an unencrypted backup). **Copy first.** **Epoch:**
> Mac-Absolute seconds, REAL/fractional (`+978307200`) on `start_date`/`end_date`. `data_type` is a numeric
> code — profile it first; sleep category = `data_type 63`.

**Profile data_type codes present in this image** — [[10-health-and-fitness]]
```sql
SELECT data_type, COUNT(*) AS n,
       datetime(MIN(start_date)+978307200,'unixepoch') AS first,
       datetime(MAX(start_date)+978307200,'unixepoch') AS last
FROM samples GROUP BY data_type ORDER BY n DESC;
```

**Complete quantity-reading join** (value + unit) — [[10-health-and-fitness]]
```sql
SELECT samples.data_id, samples.data_type,
       datetime(samples.start_date+978307200,'unixepoch') AS start,
       datetime(samples.end_date+978307200,'unixepoch')   AS end,
       quantity_samples.quantity, unit_strings.unit_string
FROM samples
JOIN quantity_samples ON quantity_samples.data_id=samples.data_id
LEFT JOIN unit_strings ON unit_strings.ROWID=quantity_samples.original_unit
ORDER BY samples.start_date;
```

**Pedometer step samples** (parameterized `data_type`) — [[07-connectivity-power-sensors-dfu]]
```sql
SELECT datetime(start_date+978307200,'unixepoch','localtime') AS start,
       datetime(end_date+978307200,'unixepoch','localtime')   AS end,
       quantity
FROM samples JOIN quantity_samples USING(data_id)
WHERE data_type = ? ORDER BY start DESC LIMIT 20;
```

**Asleep windows from category samples** (`data_type 63`, sleep values) — [[10-health-and-fitness]]
```sql
SELECT datetime(s.start_date+978307200,'unixepoch') AS start,
       datetime(s.end_date+978307200,'unixepoch')   AS end, c.value
FROM samples s JOIN category_samples c ON c.data_id=s.data_id
WHERE s.data_type = 63 AND c.value IN (1,3,4,5) ORDER BY s.start_date;
```

**Device + OS pairing/upgrade history from provenance** — [[10-health-and-fitness]]
```sql
SELECT dp.origin_product_type AS device, dp.source_version AS os_version, COUNT(*),
       datetime(MIN(o.creation_date)+978307200,'unixepoch') AS first_seen,
       datetime(MAX(o.creation_date)+978307200,'unixepoch') AS last_seen
FROM objects o JOIN data_provenances dp ON dp.ROWID=o.provenance
GROUP BY device, os_version ORDER BY first_seen;
```

**Per-sample metadata** (EAV; can carry location) — [[10-health-and-fitness]]
```sql
SELECT mk.key, mv.string_value, mv.numerical_value,
       datetime(mv.date_value+978307200,'unixepoch') AS date_value
FROM metadata_values mv JOIN metadata_keys mk ON mk.ROWID=mv.key_id
WHERE mv.object_id = :data_id;
```

---

## Third-party messaging

> These live in app or app-group containers. **Copy first.** Always discover the schema (`SELECT name FROM
> sqlite_master WHERE type='table';`) before querying — third-party schemas drift across versions.

### WhatsApp — `ChatStorage.sqlite` — [[11-third-party-app-methodology]]

> App-group container (`AppDomainGroup-…`). **Epoch:** Mac-Absolute seconds (`+978307200`).

**Chat transcript with media path** — [[11-third-party-app-methodology]]
```sql
SELECT cs.ZPARTNERNAME, m.ZISFROMME,
       datetime(m.ZMESSAGEDATE+978307200,'unixepoch','localtime') AS t,
       m.ZTEXT, mi.ZMEDIALOCALPATH
FROM ZWAMESSAGE m
JOIN ZWACHATSESSION cs ON m.ZCHATSESSION=cs.Z_PK
LEFT JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE=m.Z_PK
ORDER BY m.ZMESSAGEDATE DESC LIMIT 50;
```

### Signal — `signal.sqlite` (SQLCipher) — [[11-third-party-app-methodology]]

> **Encrypted with SQLCipher** — recover the key from the Keychain first, then decrypt to a plaintext copy.
> **Epoch:** Unix milliseconds (`/1000`) once decrypted.

**Decrypt to a plain DB** (run inside the `sqlcipher` shell) — [[11-third-party-app-methodology]]
```sql
PRAGMA key = "x'<64-hex>'";
PRAGMA cipher_plaintext_header_size = 32;
ATTACH DATABASE 'signal_plain.sqlite' AS plain KEY '';
SELECT sqlcipher_export('plain');
DETACH DATABASE plain;
```

### Telegram — `db_sqlite` (Postbox) — [[11-third-party-app-methodology]]

> Postbox key-value store; message records are **serialized blobs** (decode after extraction). Epoch: Unix
> seconds *inside* the blob.

**Pull a raw message-record blob** — [[11-third-party-app-methodology]]
```sql
SELECT quote(value) FROM t7 LIMIT 1;
```

---

## Security & privacy

### `TCC.db` (privacy consent ledger) — [[05-the-sandbox-and-tcc]]

> Per-app camera/photos/contacts/location/mic grants. **Copy first.** **Epoch trap:** `access.last_modified`
> is **plain Unix seconds** — use `'unixepoch'` with **NO** `+978307200` (adding it shifts ~31 years to ~2057).
> `auth_value`: 0 denied, 1 unknown, 2 allowed, 3 limited.

**Confirm the `access` schema for this build** (columns drift) — [[05-the-sandbox-and-tcc]]
```sql
PRAGMA table_info(access);
```

**Per-app privacy decision + when it last changed** — [[05-the-sandbox-and-tcc]]
```sql
SELECT service, client,
       CASE auth_value WHEN 0 THEN 'denied' WHEN 1 THEN 'unknown'
                       WHEN 2 THEN 'allowed' WHEN 3 THEN 'limited' END AS decision,
       auth_reason,
       datetime(last_modified,'unixepoch') AS changed_utc
FROM access ORDER BY last_modified DESC;
```

### `keychain-2.db` (device keychain) — [[08-keychain-on-ios]], [[05-full-file-system-acquisition]]

> **Path:** `/private/var/Keychains/keychain-2.db` (outside every app container). **Copy first.** Rows
> enumerate but `data` is **wrapped** — secrets need on-device key material (or an encrypted-backup keychain +
> decrypt). **Epoch:** Mac-Absolute seconds (`+978307200`) on `cdat`/`mdat` (NOT nanoseconds — `/1e9` here
> yields dates decades off). `pdmn` = protection class (a `…u` suffix = device-only / non-portable); a non-empty
> `tkid` = SEP-bound; a non-empty `accc` = ACL-gated.

**Triage generic-password items + creation date** — [[08-keychain-on-ios]]
```sql
SELECT rowid, agrp, svce, acct, pdmn, sync,
       datetime(cdat + 978307200, 'unixepoch', 'localtime') AS created,
       length(data) AS data_len
FROM genp ORDER BY cdat DESC LIMIT 30;
```

**Per-row fate** (SEP-bound? ACL-gated? leaves the device?) — [[08-keychain-on-ios]]
```sql
SELECT agrp, pdmn, sync, tomb,
       CASE WHEN tkid IS NOT NULL AND tkid != '' THEN 'SEP' ELSE '' END AS sep_bound,
       CASE WHEN accc IS NOT NULL AND length(accc) > 0 THEN 'ACL' ELSE '' END AS access_ctrl,
       CASE WHEN pdmn LIKE '%u' THEN 'device-only' ELSE 'portable' END AS portability
FROM genp ORDER BY agrp;
```

**Protection-class census** (no decryption needed) — [[08-keychain-on-ios]]
```sql
SELECT pdmn, count(*) FROM genp GROUP BY pdmn;
```

**Map keychain access-groups** (which apps own credentials) — [[05-full-file-system-acquisition]]
```sql
SELECT agrp, COUNT(*) FROM genp GROUP BY agrp ORDER BY 2 DESC LIMIT 20;
```

**Prove the `data` blob is wrapped** (version prefix) — [[08-keychain-on-ios]]
```sql
SELECT quote(substr(data,1,8)) FROM genp LIMIT 5;
```

**Confirm `pdmn` tracks the requested `kSecAttrAccessible`** (lab) — [[08-keychain-on-ios]]
```sql
SELECT acct, pdmn, sync FROM genp WHERE svce='lab.keychain.demo';
```

**List certificates / export a cert DER** — [[08-keychain-on-ios]]
```sql
SELECT rowid, length(data) AS der_len, hex(substr(labl,1,16)) FROM cert;
SELECT writefile('/tmp/c.der', data) FROM cert WHERE rowid=<N>;   -- then: openssl x509 -inform DER -in /tmp/c.der -text
```

**Dump genp / inet column shape** — [[08-keychain-on-ios]]
```sql
PRAGMA table_info(genp); PRAGMA table_info(inet);
```

### `TrustStore.sqlite3` (Simulator cert trust) — [[02-traffic-interception-and-tls]]

**Extract a trusted cert's DER to recompute its fingerprint** — [[02-traffic-interception-and-tls]]
```sql
SELECT writefile('/tmp/row.der', data) FROM tsettings LIMIT 1;
```

---

## Networking & accounts

### `netusage.sqlite` / `DataUsage.sqlite` (per-process network I/O) — [[00-the-ios-networking-stack]], [[12-unified-logs-sysdiagnose-crash-network]]

> **Copy first.** **Epoch:** Mac-Absolute / CFAbsoluteTime seconds (`+978307200`) on
> `ZTIMESTAMP`/`ZFIRSTTIMESTAMP`. `ZPROCESS.ZFIRSTTIMESTAMP` for a deleted app's bundle is a strong
> "this app once ran / was installed" tell. (Also an `mvt` spyware-triage signal.)

**Per-process bytes timeline / top talkers** (`netusage.sqlite`) — [[00-the-ios-networking-stack]]
```sql
SELECT P.ZPROCNAME,
       datetime(U.ZTIMESTAMP + 978307200, 'unixepoch', 'localtime') AS ts,
       U.ZWIFIIN, U.ZWIFIOUT, U.ZWWANIN, U.ZWWANOUT
FROM ZLIVEUSAGE U JOIN ZPROCESS P ON U.ZHASPROCESS = P.Z_PK
ORDER BY U.ZTIMESTAMP DESC LIMIT 25;
```

**First/last-seen per cellular process** (deleted-app tell) (`DataUsage.sqlite`) — [[00-the-ios-networking-stack]]
```sql
SELECT P.ZPROCNAME, P.ZBUNDLENAME,
       datetime(P.ZFIRSTTIMESTAMP + 978307200, 'unixepoch','localtime') AS first_seen,
       datetime(P.ZTIMESTAMP + 978307200, 'unixepoch','localtime')      AS last_seen
FROM ZPROCESS P ORDER BY P.ZFIRSTTIMESTAMP;
```

**Per-process WWAN bytes + first/last seen** (joined rollup) (`DataUsage.sqlite`) — [[12-unified-logs-sysdiagnose-crash-network]]
```sql
SELECT p.ZPROCNAME, p.ZBUNDLENAME,
       datetime(p.ZFIRSTTIMESTAMP+978307200,'unixepoch') AS first_seen,
       datetime(p.ZTIMESTAMP+978307200,'unixepoch')      AS last_seen,
       SUM(u.ZWWANIN), SUM(u.ZWWANOUT)
FROM ZPROCESS p LEFT JOIN ZLIVEUSAGE u ON u.ZHASPROCESS=p.Z_PK
GROUP BY p.Z_PK ORDER BY p.ZFIRSTTIMESTAMP;
```

### `CellularUsage.db` (SIM / ICCID succession) — [[06-cellular-baseband-esim-and-identifiers]]

> **Epoch:** Mac-Absolute seconds (`+978307200`) on `last_update_time`. SIM-swap / number-change history.

**Timestamped SIM/ICCID succession** — [[06-cellular-baseband-esim-and-identifiers]]
```sql
SELECT slot_id, subscriber_id AS iccid, subscriber_mdn AS phone_number,
       datetime(last_update_time + 978307200,'unixepoch','localtime') AS last_used
FROM subscriber_info ORDER BY last_update_time DESC;
```

### `Accounts3.sqlite` / `Accounts4.sqlite` (configured accounts) — [[07-apple-account-icloud-and-apns]], [[13-notifications-keyboard-and-misc-stores]], [[04-continuity-with-the-mac]], [[06-icloud-acquisition-and-advanced-data-protection]], [[05-full-file-system-acquisition]]

> **Epoch:** Mac-Absolute seconds (`+978307200`) on `ZDATE`. `Accounts3.sqlite` is the iOS store;
> `Accounts4.sqlite` is the macOS counterpart (cross-device match). The `ZACCOUNTTYPE` join gives the
> human-readable type.

**Every configured account + date added** (full join) — [[07-apple-account-icloud-and-apns]], [[13-notifications-keyboard-and-misc-stores]]
```sql
SELECT a.ZUSERNAME AS username,
       at.ZACCOUNTTYPEDESCRIPTION AS type,
       a.ZACCOUNTDESCRIPTION AS descr,
       a.ZOWNINGBUNDLEID AS owner_bundle,
       a.ZIDENTIFIER,
       datetime(a.ZDATE + 978307200,'unixepoch','localtime') AS date_added
FROM ZACCOUNT a
LEFT JOIN ZACCOUNTTYPE at ON a.ZACCOUNTTYPE = at.Z_PK
ORDER BY a.ZDATE;
```

**Quick account list** (incl. Apple Account) — [[04-continuity-with-the-mac]], [[06-icloud-acquisition-and-advanced-data-protection]]
```sql
SELECT ZUSERNAME, ZIDENTIFIER, ZACCOUNTDESCRIPTION FROM ZACCOUNT;
```

---

## App state & system stores

### `applicationState.db` (FrontBoard) — [[00-app-sandbox-and-filesystem-layout]], [[01-windowing-multitasking-and-external-display]], [[13-notifications-keyboard-and-misc-stores]], [[04-the-app-bundle-and-ipa-structure]]

> **Path:** `/private/var/mobile/Library/FrontBoard/applicationState.db`. **Copy first.** Maps bundle ID ↔
> container path; the path itself lives in the `compatibilityInfo` **bplist BLOB** inside `kvs`. `_UninstallDate`
> (Mac-Absolute NSDate, `+978307200`) proves when an app was deleted; `XBApplicationSnapshotManifest` =
> app-switcher inventory.

**Bundle-ID inventory** — [[01-windowing-multitasking-and-external-display]], [[13-notifications-keyboard-and-misc-stores]]
```sql
SELECT * FROM application_identifier_tab LIMIT 40;
```

**Per-app kvs blob sizes** (compatibilityInfo / _UninstallDate / snapshot manifest) — [[00-app-sandbox-and-filesystem-layout]], [[01-windowing-multitasking-and-external-display]], [[04-the-app-bundle-and-ipa-structure]]
```sql
SELECT ait.application_identifier AS bundle_id,
       kt.key AS key_name,
       length(kvs.value) AS blob_bytes
FROM kvs
JOIN application_identifier_tab ait ON kvs.application_identifier = ait.id
JOIN key_tab kt ON kvs.key = kt.id
WHERE kt.key IN ('compatibilityInfo','_UninstallDate','XBApplicationSnapshotManifest')
ORDER BY bundle_id;
```

**Extract one kvs / compatibilityInfo BLOB to disk** (then `plutil -p`) — [[00-app-sandbox-and-filesystem-layout]], [[01-windowing-multitasking-and-external-display]]
```sql
-- by bundle + key (container path lives here):
SELECT writefile('/tmp/compat.plist', kvs.value)
FROM kvs
JOIN application_identifier_tab ait ON kvs.application_identifier = ait.id
JOIN key_tab kt ON kvs.key = kt.id
WHERE ait.application_identifier='com.foo.Bar' AND kt.key='compatibilityInfo';
-- or first blob, quick:
SELECT writefile('/tmp/blob.bplist', value) FROM kvs LIMIT 1;
```

### `Shortcuts.sqlite` (Shortcuts automation) — [[00-shortcuts-and-the-automation-surface]]

> **Epoch:** Mac-Absolute seconds (`+978307200`) on `ZCREATIONDATE`/`ZMODIFICATIONDATE`/`ZLASTRUNEVENTDATE`.

**List shortcuts with creation/modification dates** — [[00-shortcuts-and-the-automation-surface]]
```sql
SELECT Z_PK, ZNAME,
       datetime(ZCREATIONDATE + 978307200,'unixepoch','localtime') AS created,
       datetime(ZMODIFICATIONDATE + 978307200,'unixepoch','localtime') AS modified
FROM ZSHORTCUT ORDER BY ZMODIFICATIONDATE DESC;
```

**Dump a shortcut's action-graph blob** (no export / no signature) — [[00-shortcuts-and-the-automation-surface]]
```sql
SELECT writefile('/tmp/actions.bplist', ZDATA) FROM ZSHORTCUTACTIONS WHERE Z_PK=1;
```

### `RMAdminStore-Local.sqlite` (Screen Time) — [[01-screen-time-and-content-privacy-restrictions]]

> **Epoch:** Mac-Absolute seconds (`+978307200`) on `ZUSAGEBLOCK.ZSTARTDATE`/`ZENDDATE`. Family-wide usage
> rollup across the whole join chain.

**Per-member / per-device / per-app(-domain) / per-category usage** — [[01-screen-time-and-content-privacy-restrictions]]
```sql
SELECT cu.ZNAME AS family_member, cd.ZNAME AS device,
       cat.ZIDENTIFIER AS category, item.ZBUNDLEIDENTIFIER AS app_or_domain,
       datetime(blk.ZSTARTDATE + 978307200,'unixepoch') AS block_start_utc,
       datetime(blk.ZENDDATE + 978307200,'unixepoch')   AS block_end_utc,
       item.ZTOTALTIME AS seconds_used
FROM ZUSAGETIMEDITEM item
JOIN ZUSAGECATEGORY cat ON item.ZCATEGORY = cat.Z_PK
JOIN ZUSAGEBLOCK blk    ON cat.ZBLOCK = blk.Z_PK
JOIN ZUSAGE u           ON blk.ZUSAGE = u.Z_PK
JOIN ZCOREDEVICE cd     ON u.ZDEVICE = cd.Z_PK
JOIN ZCOREUSER cu       ON u.ZCOREUSER = cu.Z_PK
ORDER BY blk.ZSTARTDATE DESC LIMIT 100;
```

### Files app & iCloud Drive — `smartfolders.db` / CloudDocs `client.db` — [[02-files-external-storage-and-document-providers]]

> CloudDocs `client.db`/`server.db` timestamps are **mixed per-column** — verify each (often Mac-Absolute,
> sometimes Unix or text).

**Enumerate Files-app bookkeeping tables** (`smartfolders.db`) — [[02-files-external-storage-and-document-providers]]
```sql
SELECT name FROM sqlite_master WHERE type='table';
```

**Files this device uploaded to iCloud Drive** (exfiltration signal) (`client.db`) — [[02-files-external-storage-and-document-providers]]
```sql
SELECT * FROM client_uploads LIMIT 20;
```

### `UserDictionary.sqlite` (Text-Replacement / learned words) — [[03-trackpad-keyboard-and-apple-pencil]]

**Read user dictionary entries** (discover table name first) — [[03-trackpad-keyboard-and-apple-pencil]]
```sql
SELECT * FROM <table> LIMIT 20;
```

### `default.store` (SwiftData / Core Data) — [[02-swift-swiftui-uikit-and-app-architecture]]

> A third-party app's own Core Data SQLite. **Epoch:** Core Data date columns are Mac-Absolute seconds
> (`+978307200`). Map the auto-generated `Z`-schema first.

**List all tables to map the Z-schema** — [[02-swift-swiftui-uikit-and-app-architecture]]
```sql
SELECT name FROM sqlite_master WHERE type='table';
```

**Convert a Core Data Mac-Absolute date column to local time** — [[02-swift-swiftui-uikit-and-app-architecture]]
```sql
SELECT datetime(ZCREATEDAT + 978307200, 'unixepoch', 'localtime') FROM ZTASK;
```

---

## Bluetooth — `ledevices.paired.db` — [[05-radios-wifi-bt-nfc-uwb]], [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]]

> **Path:** `…/SystemGroup/<GUID>/Library/Database/com.apple.MobileBluetooth.ledevices.paired.db` (paired LE);
> sibling `…ledevices.other.db` holds devices merely *seen* in range (ambient co-presence). **Copy first.**
> **Epoch:** Mac-Absolute seconds (`+978307200`) on `LastSeenTime`/`LastConnectionTime` (verify — Bluetooth's
> `LastSeenTime` is a documented local-time exception in the plist sibling). The `PairedDevices` table carries
> the real (resolved) identity address, not the rotating RPA.

**Bonded LE devices** (name, resolved identity addr, last-seen) — [[04-wifi-bluetooth-and-proximity]], [[04-continuity-with-the-mac]]
```sql
SELECT * FROM PairedDevices;
```

**Read after discovering the schema** (when table name is unknown) — [[05-radios-wifi-bt-nfc-uwb]]
```sql
SELECT name FROM sqlite_master WHERE type='table';   -- then:
SELECT * FROM <table> LIMIT 50;
```

---

## Reverse engineering — `ent.db` (ipsw entitlement DB) — [[01-the-code-signature-blob-and-entitlements-on-ios]]

> Built by `ipsw ent --create-db` over an IPSW's binaries — a searchable index of every system binary's
> entitlements. No timestamps.

**System binaries holding debug / restricted security entitlements** — [[01-the-code-signature-blob-and-entitlements-on-ios]]
```sql
SELECT p.path
FROM entitlements e
JOIN paths p ON p.id = e.path_id
JOIN entitlement_keys k ON k.id = e.key_id
WHERE k.key = 'task_for_pid-allow' OR k.key LIKE 'com.apple.private.security%'
ORDER BY p.path;
```

---

## Timeline tooling (APOLLO / Timesketch fusion)

> Working databases you build, not device evidence — [[01-building-a-unified-timeline]]. `apollo.db` is APOLLO's
> output; `timeline.db` is the fused spine. Timestamps are already normalized ISO-8601 text.

### `apollo.db` (APOLLO output) — [[01-building-a-unified-timeline]]

**Normalize APOLLO rows to Timesketch columns** — [[01-building-a-unified-timeline]]
```sql
SELECT Key AS datetime, Activity AS timestamp_desc,
       (Activity || ': ' || Output) AS message,
       Database AS source_store, 'APOLLO' AS tool
FROM APOLLO WHERE Key IS NOT NULL AND Key != '' ORDER BY Key;
```

**Count rows per contributing store** — [[01-building-a-unified-timeline]]
```sql
SELECT Database, COUNT(*) FROM APOLLO GROUP BY Database ORDER BY 2 DESC;
```

### `timeline.db` (fused spine) — [[01-building-a-unified-timeline]]

**Fused, time-sorted spine** — [[01-building-a-unified-timeline]]
```sql
SELECT datetime, source_store, message FROM tl ORDER BY datetime LIMIT 40;
```

**Flag same-event doubles within 2s across stores** (de-dupe / corroborate) — [[01-building-a-unified-timeline]]
```sql
SELECT a.datetime AS t1, b.datetime AS t2, a.source_store, b.source_store, a.message
FROM tl a JOIN tl b
  ON a.message = b.message AND a.source_store <> b.source_store
 AND ABS(strftime('%s',a.datetime) - strftime('%s',b.datetime)) <= 2
WHERE a.rowid < b.rowid ORDER BY a.datetime LIMIT 50;
```

**Pivot to an anchor window** — [[01-building-a-unified-timeline]]
```sql
SELECT datetime AS utc, source_store, message FROM tl
WHERE datetime BETWEEN '2024-03-03 21:10:00' AND '2024-03-03 21:26:00'
ORDER BY datetime;
```

**Year-distribution sanity plot** (catch epoch-conversion bugs) — [[01-building-a-unified-timeline]]
```sql
SELECT substr(datetime,1,4) AS yr, COUNT(*) FROM tl GROUP BY yr;
```

### WAL deleted-row recovery demo (throwaway `t.db`) — [[14-deleted-data-recovery]]

> Builds the canonical "deleted rows live in the `-wal`" demonstration — the reason you never discard sidecars.

```sql
PRAGMA journal_mode=WAL;
CREATE TABLE msg(id INTEGER PRIMARY KEY, body TEXT);
INSERT INTO msg(body) VALUES('keep me'),('delete me'),('also keep');
DELETE FROM msg WHERE body='delete me';   -- 'delete me' persists in t.db-wal
```

---

## Timestamp conversion recipes (the epoch zoo)

> Drop-in `SELECT`-fragment conversions to UTC (add `,'localtime'` for device-local). Full reasoning, the
> constants, and the magnitude heuristics are in [[00-the-ios-timestamp-zoo]].

| Epoch | Recipe | Applies to |
|---|---|---|
| Mac-Absolute (2001), seconds | `datetime(ZSTARTDATE + 978307200, 'unixepoch')` | knowledgeC, routined, Safari, Biome SEGB, interactionC, most `Z*DATE` |
| Mac-Absolute, nanoseconds | `datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime')` | `sms.db`/`chat.db` `date`/`date_read`/`date_delivered`/`date_edited` (iOS 11+) |
| Mac-Absolute, **magnitude-aware** ns-or-sec | `CASE WHEN message.date > 1000000000000 THEN datetime(message.date/1000000000 + 978307200,'unixepoch','localtime') ELSE datetime(message.date + 978307200,'unixepoch','localtime') END` | `sms.db` mixed-precision rows |
| Mac-Absolute → device-local via captured offset | `datetime(ZSTARTDATE + 978307200 + ZSECONDSFROMGMT, 'unixepoch')` | knowledgeC (avoids host `'localtime'`) |
| Mac-Absolute, sub-second precision kept | `strftime('%Y-%m-%d %H:%M:%f', ZSTARTDATE + 978307200, 'unixepoch')` | tie-breaking near-simultaneous events |
| Unix (1970), seconds | `datetime(x, 'unixepoch')` (no offset) | `TCC.db.last_modified`, Mail `Envelope Index`, `voicemail.date`, PowerLog raw `TIMESTAMP`, MBFile mtimes |
| Unix day-bucket | `DATE(DAYSSINCE1970*86400, 'unixepoch')` | Aggregate Dictionary `ADDataStore.sqlitedb` |
| Unix milliseconds | `datetime(x/1000, 'unixepoch')` | Signal/Snapchat, cross-platform JS/Java columns |
| Unix microseconds | `datetime(x/1000000, 'unixepoch')` | some third-party app columns |
| WebKit/Chrome (1601), microseconds | `datetime(last_visit_time/1000000 - 11644473600, 'unixepoch', 'localtime')` | Chrome/Chromium `History`, some WebKit caches |
| Firefox PRTime (1970), microseconds | `datetime(visit_date/1000000, 'unixepoch')` | Firefox `moz_places`/`moz_historyvisits` |
| APFS inode (1970), nanoseconds | `datetime(create_time/1000000000, 'unixepoch')` | `j_inode_val_t` create/mod/change/access times |
| HFS+ legacy (1904), seconds | `datetime(hfs_time - 2082844800, 'unixepoch')` | old HFS+ volumes, carved structures |

**Key constants:** `978307200` (1970→2001) · `11644473600` (1601→1970, WebKit/FILETIME) · `2082844800`
(1904→1970, HFS). **Show-your-work check** (correct vs forgot-divide vs forgot-offset) — [[00-the-ios-timestamp-zoo]]:
```sql
SELECT message.date AS raw,
       datetime(message.date/1000000000 + 978307200,'unixepoch') AS correct,
       datetime(message.date + 978307200,'unixepoch')            AS forgot_div,
       datetime(message.date/1000000000,'unixepoch')             AS forgot_off
FROM message ORDER BY date DESC LIMIT 5;
```
