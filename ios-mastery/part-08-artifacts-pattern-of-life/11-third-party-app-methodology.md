---
title: "Third-party app methodology"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 11
est_time: "50 min read + 20 min labs"
prerequisites: [app-sandbox-and-filesystem-layout, communications-imessage-and-sms]
tags: [ios, forensics, third-party-apps, whatsapp, signal, sqlcipher, methodology, dfir]
last_reviewed: 2026-06-26
---

# Third-party app methodology

> **In one sentence:** You will always face an app no parser covers, so the durable skill is not a memorized schema but a repeatable loop — resolve the container, inventory the stores, fingerprint each store's *format*, locate any decryption key (usually in the Keychain), then parse — and this lesson teaches that loop across the full format spectrum (plain SQLite → SQLCipher → plist → protobuf → LevelDB → custom postbox).

## Why this matters

The Apple first-party stores in the rest of Part 08 — `knowledgeC`/Biome, Photos, the call/SMS DBs — are catalogued to death; iLEAPP, mac_apt, and every commercial suite ship turnkey parsers for them. Third-party apps are where examinations actually go to die. There are millions of apps, their on-disk layouts change between point releases, and the one app that matters in *your* case — a niche dating app, a crypto wallet, a piece of nation-state spyware, an obscure regional messenger — is exactly the one no vendor has reversed yet. A forensicator who can only run the GUI's "WhatsApp" button is helpless the moment the target deviates. The transferable method below is what separates a button-pusher from someone who can sit down in front of an unknown container and *derive* the evidence. The specific schemas in this lesson (WhatsApp's `ZWAMESSAGE`, Signal's `GRDBDatabaseCipherKeySpec`) will rot; treat them as worked examples of the method, not as facts to memorize.

There's a second payoff beyond the obvious-app case. The same container-walk is your **anomaly hunt**: a container whose bundle ID resolves to nothing in the App Store, an app with broad entitlements and a tiny UI, a store full of encrypted blobs and outbound-network caches in an app that has no business phoning home — these are how implants and unwanted commercial spyware surface. Knowing the *normal* shape of a third-party container (what stores a legit messenger keeps, where, and in what format) is what lets you spot the abnormal one. The loop is dual-use: it parses the app you expect and flags the one you didn't.

## Concepts

### The transferable loop

Every third-party app investigation, regardless of platform, is the same six-step loop. Burn this in — everything else is detail:

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 1. RESOLVE   opaque-UUID container  ->  bundle ID (which app is this?) │
 │ 2. INVENTORY walk Documents/ Library/ tmp/ + the Shared App Group(s)   │
 │ 3. FINGERPRINT each candidate store -> SQLite? SQLCipher? plist?       │
 │              protobuf? Realm? LevelDB? custom binary?                   │
 │ 4. KEY       if encrypted, where is the key?  (almost always Keychain) │
 │ 5. PARSE     decode with the right tool for the format                 │
 │ 6. TIMESTAMP normalize every time field to the correct epoch           │
 └──────────────────────────────────────────────────────────────────────┘
```

Steps 1–4 are *format recognition* — a transferable skill you already own from macOS. Steps 5–6 are mechanical once you know the format. The whole game is getting fast and confident at 1–4 so that an app you have never seen takes minutes, not days.

> 🖥️ **macOS contrast:** On the Mac you studied `~/Library/Containers/<bundle-id>/Data/` — sandboxed app data filed under a *human-readable* reverse-DNS folder name, so step 1 was free (the folder literally says `com.tinyspeck.slackmacgap`). iOS files the identical structure under an **opaque UUID** (`.../Containers/Data/Application/8F2A…/`) with the bundle ID hidden inside a metadata plist. The store-type recognition you learned there — "is this a SQLite DB, a binary plist, a SQLCipher blob?" — is *exactly* the same; iOS just strips the signpost off the front door so step 1 becomes real work.

### Step 1 — Resolve the container (UUID → bundle)

On a full-filesystem image (see [[05-full-file-system-acquisition]]) third-party data lives under three roots, all keyed by a randomly assigned UUID, **not** the bundle ID:

| Root | Holds | Path (device) |
|---|---|---|
| Bundle | the signed `.app` (read-only, code) | `/private/var/containers/Bundle/Application/<UUID>/<App>.app/` |
| Data | the app's private sandbox (the evidence) | `/private/var/mobile/Containers/Data/Application/<UUID>/` |
| Shared | App Group containers shared by an app + its extensions | `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/` |

Four independent ways to map a UUID back to a bundle ID — cross-check them, because a mismatch is itself an artifact:

1. **The per-container metadata plist.** Every Data and Shared container holds a hidden `.com.apple.mobile_container_manager.metadata.plist` at its root. Its `MCMMetadataIdentifier` key is the bundle ID (for a Data container) or the App Group ID (for a Shared container, e.g. `group.net.whatsapp.WhatsApp.shared`). This is the ground truth — read it first.
2. **`applicationState.db`** — SQLite at `/private/var/mobile/Library/FrontBoard/applicationState.db`. Maps bundle IDs to their container UUIDs (and carries last-run/snapshot state). Survives app *backgrounding*; useful when a container is otherwise ambiguous.
3. **The MobileInstallation maps** — `installd`'s bookkeeping under `/private/var/installd/Library/MobileInstallation/` (notably `LastLaunchServicesMap.plist`) maps each bundle ID to both its Bundle and Data container paths. *(Exact filename has drifted across iOS majors — verify against your image's OS version.)*
4. **The bundle's own `Info.plist`** — `CFBundleIdentifier` inside `<UUID>/<App>.app/Info.plist` names the app directly, and `WKAppBundleIdentifier`/`com.apple.security.application-groups` entitlements in the embedded code signature list the App Groups it owns — your bridge from a Bundle UUID to the *Shared* UUID where the real DB hides.

> 🔬 **Forensics note:** The Bundle UUID and the Data UUID are **different** and both change on reinstall. An app deleted and reinstalled gets fresh UUIDs and a fresh empty container — but the *old* container may linger un-reaped on disk for a while, and `applicationState.db` / FrontBoard may still reference the dead UUID. Two containers for the same bundle ID = a reinstall event with a recoverable "before" state. Always enumerate *all* containers, not just the live one.

### Step 2 — Inventory the stores

Inside a Data container you'll find Apple's standard sandbox skeleton ([[00-app-sandbox-and-filesystem-layout]]):

```
Containers/Data/Application/<UUID>/
├── Documents/            user-visible files (backed up; often the primary DB)
├── Library/
│   ├── Application Support/   developer's durable stores (DBs, caches)
│   ├── Caches/               purgeable; NOT backed up, but rich at acquisition time
│   ├── Preferences/          <bundle-id>.plist  ← NSUserDefaults
│   └── ...
├── SystemData/
├── tmp/                   scratch; volatile but often holds in-flight media
└── .com.apple.mobile_container_manager.metadata.plist
```

The *trap*: for messengers the headline database is frequently **not** in the Data container at all — it's in the **Shared App Group**, because the message store must be reachable by the Notification Service / Share extensions. WhatsApp, Signal, and Telegram all do this. If you only grep the Data container you will miss the entire chat history. Always enumerate the App Group(s) the app declares.

Walk it mechanically and record three things per file: **path, size, and format** (next step). Don't open anything yet.

### Step 3 — Fingerprint the format

This is the heart of the method. Identify each store by its **magic bytes**, never by its extension — apps lie with extensions constantly (a `.db` that is actually SQLCipher, a `.dat` that is a protobuf, a `.sqlite` that is a Realm file). The first 16 bytes settle it:

| Format | Magic / signature (first bytes) | Tell | Tool to parse |
|---|---|---|---|
| **SQLite 3** | `53 51 4C 69 74 65 20 66 6F 72 6D 61 74 20 33 00` = `SQLite format 3\0` | plaintext header at offset 0 | `sqlite3`, iLEAPP |
| **SQLCipher / encrypted SQLite** | high-entropy from byte 0 (no `SQLite format 3`) **but** a `-wal`/`-shm` alongside and a sane page-aligned size | looks like noise; needs a key | `sqlcipher` + Keychain key |
| **Binary plist** | `62 70 6C 69 73 74 30 30` = `bplist00` | `bplist00` | `plutil`/`plistutil`, `ccl_bplist` |
| **XML plist** | `<?xml` / `<plist` | text | `plutil`, any editor |
| **Protocol Buffers** | *no* fixed magic — field-tag bytes (`0a`, `12`, `1a`…) | structured but no header | `protoc --decode_raw`, `blackboxprotobuf` |
| **LevelDB** | dir of `*.ldb`/`*.log` + `MANIFEST-*`, `CURRENT` | a *folder*, not a file | `ccl_leveldb`, `plyvel` |
| **Realm** | `54 2D 44 42` = `T-DB` mnemonic at **offset 16** (bytes 0–15 are two 8-byte top-ref pointers, *not* magic) | no first-byte magic; `sqlite3` refuses it, `file` says "Realm" | Realm Studio / `realm` SDK |
| **Mach-O / image / media** | `cf fa ed fe`, `ff d8 ff` (JPEG), `00 00 00 …ftyp` (MP4/HEIC) | — | `file`, `exiftool` |

The rule that never fails: **`file` the thing, then `xxd | head` the thing, then decide.** A SQLCipher database is just "a file that *should* be SQLite by context (it has WAL siblings, it's named `signal.sqlite`) but whose first bytes are entropy instead of `SQLite format 3`." That single observation — header is noise where a header should be — is your encrypted-store detector for *any* app, not just Signal.

> 🔬 **Forensics note:** WAL and SHM sidecars (`-wal`, `-shm`) are evidence in their own right and **part of the store** — copy them with the main DB. The `-wal` (write-ahead log) holds committed-but-not-yet-checkpointed rows, which for messengers routinely means **deleted and edited messages that no longer exist in the main B-tree.** This is true for SQLCipher too (the WAL is encrypted with the same key). Never query a DB whose WAL you left behind: at best you miss data, at worst your read triggers a checkpoint that destroys it. Copy main + `-wal` + `-shm` together, every time. See [[14-deleted-data-recovery]].

### Step 4 — Where the key lives

If step 3 says "encrypted," you need the key before step 5 means anything. Decision tree, in order of likelihood:

1. **The iOS Keychain.** By far the most common. The app generates a random DB key once and stores it as a Keychain item; the *database file* is portable junk without it. This is why a logical backup of an encrypted messenger is often useless — the file is there, the Keychain item is not (backups only include Keychain items whose protection class permits, and many are device-only). You need a **full-filesystem acquisition that also dumps the Keychain** ([[08-keychain-on-ios]]), which in turn needs the device unlocked at least once since boot (AFU, not BFU — see [[03-passcode-bfu-afu-and-inactivity]]). The Keychain item's own protection class (e.g. `AfterFirstUnlock` vs `WhenUnlockedThisDeviceOnly`) decides whether it's even extractable and whether it left the device in a backup. This is the single most important fact in encrypted-app forensics: **the data's recoverability is gated by the *key's* Data Protection class, not the database's.**
2. **Derived from the passcode / a user secret.** Some apps (password managers, encrypted notes) derive the key via PBKDF2/Argon2 from a user-entered passphrase that is *not* stored. No key on disk → you need the passphrase (consent, or a guided/brute-force attack on the KDF parameters).
3. **In a plist or the file itself.** Weaker apps store the key in NSUserDefaults, a config plist, or even hardcoded/obfuscated in the binary. Always worth a grep; embarrassingly often productive.
4. **Hardware-bound (SEP).** Keys wrapped by the Secure Enclave are non-exportable; you can only use them *on the live, unlocked device* (e.g. via a Frida hook that asks the running app to decrypt for you — see [[05-dynamic-analysis-with-frida]]). Off-device decryption is impossible by design.

> 🖥️ **macOS contrast:** On the Mac, an encrypted app DB's key was often sittable-out with `security find-generic-password -s '<service>' -w` against the *login keychain* — a single SQLite-backed file (`login.keychain-db`) you could unlock with the user's password and dump from userland. iOS has no equivalent CLI and no single dumpable keychain file in a backup: keychain items are individually wrapped by class keys tied to the passcode and (for the higher classes) the SEP, so "get the app's DB key" escalates from a one-liner into a full-filesystem-acquisition-plus-keychain-decryption problem gated by device lock state. Same *concept* (per-app secret in the OS keystore), radically harder *acquisition*.

> ⚖️ **Authorization:** Pulling a per-app DB key out of the Keychain, then decrypting a SQLCipher messenger, is a content interception. Confirm your warrant/authority covers stored *communications content* for that application and account — many authorizations are scoped to metadata or to specific apps. Log the Keychain item you extracted (by `kSecAttrService`/`kSecAttrAccount`, not the secret value) in your notes, and image before you touch anything.

### The two non-SQL stores you'll actually hit: Realm & LevelDB/IndexedDB

SQLite dominates, but two non-SQL stores show up constantly and trip up examiners who only know `sqlite3`. Recognize them so step 3 doesn't dead-end.

**Realm** is an object database popular with apps built on shared cross-platform codebases. A `.realm` file has its own header (it is *not* SQLite — `sqlite3` will refuse it), holds a self-describing schema, and is read with **Realm Studio** or the Realm SDK. The forensic catch mirrors Signal: **encrypted Realm** uses a 64-byte key (AES-256-CBC + HMAC-SHA-224) that the app almost always parks in the **Keychain** — same step-4 dependency, same "DB-is-noise-without-the-key" problem, different toolchain. Look for `default.realm`, `*.realm.lock`, and a `*.realm.management/` directory alongside.

**LevelDB** is Google's key/value store, and you meet it from two directions on iOS:
1. **Native LevelDB** — used directly by some apps (and by React Native's `AsyncStorage`) as a folder of `*.ldb`/`*.log` + `MANIFEST-*` + `CURRENT`. Parse with `ccl_leveldb` (Alex Caithness) or `plyvel`.
2. **WKWebView IndexedDB** — any app embedding a web view (hybrid apps, in-app browsers, Electron-style wrappers) stores its **IndexedDB** as LevelDB under the app's WebKit storage tree (`Library/WebKit/.../IndexedDB/` or a `WebsiteData` path). Here the values are *Chromium/WebKit-serialized objects* layered on top of LevelDB — a two-format-deep store. `ccl_chromium_reader` (Caithness; formerly `ccl_chrome_indexeddb`) handles the serialization on top of the raw key/value pairs.

The recurring methodological note: a *folder* that contains `CURRENT` and `MANIFEST-*` is a LevelDB, not a junk cache — and like Telegram's Postbox, the container format (LevelDB) and the payload format (the serialized object inside each value) are **two separate parsing problems**.

### Generalizing: an app no catalog covers

This is the whole point — apply the loop to something iLEAPP has never heard of (a niche dating app, a crypto wallet, a spyware implant). The procedure is identical; only the answers change:

1. **Resolve & enumerate** every container for the bundle ID — Data, Shared App Group(s), and any orphaned (reinstall) UUIDs. Read the entitlements in the `.app` to discover which App Groups even exist.
2. **Inventory & fingerprint** every file. Build a table: path / size / true format. For a crypto wallet you might find a SQLite "wallet.db", a `bplist00` config, a `keystore` blob, and a `.realm` transaction cache — four formats, four sub-tasks.
3. **For each encrypted store, run the step-4 tree.** Grep the Data container and `NSUserDefaults` plist for likely key names (`*key*`, `*secret*`, `*cipher*`, base64-looking values). Dump the Keychain and diff item names against the app's bundle ID prefix. If nothing on disk, suspect a passphrase-derived or SEP-bound key and pivot to a live-device Frida approach.
4. **Decode payloads, not just containers.** A SQLite full of protobuf blobs, a plist whose value is a nested bplist, a LevelDB of serialized objects — descend until you reach plaintext fields.
5. **Pin the epoch** of every timestamp before you believe a single one ([[00-the-ios-timestamp-zoo]]), and corroborate against Apple's own stores — even a fully-encrypted app leaks its *usage* into [[01-knowledgec-db-deep-dive]] and its *notification text* into [[13-notifications-keyboard-and-misc-stores]].

If you can do those five against a binary you've never seen, you have the actual skill this lesson exists to build.

> ⚠️ **ADVANCED:** When the key is SEP-bound or passphrase-derived and off-device decryption is impossible, the only path is *live* — attach Frida to the running, unlocked app and hook its own decrypt routine to dump plaintext (or the resolved key) as the app produces it ([[05-dynamic-analysis-with-frida]]). This is device-bound, mutates a running process, and on A14+ has no public BootROM/jailbreak foothold to inject from — so it is a consent-device or lab-device technique, not a dead-box one. Document it as an alteration of the live system and never as a clean acquisition.

> 🔬 **Forensics note:** Before declaring an unknown app "encrypted, unrecoverable," prove the negative properly. Re-fingerprint after checking for a *plaintext sibling*: many apps keep an encrypted primary DB but a cleartext cache, search index, or analytics SQLite right next to it that mirrors enough content to reconstruct the case. The receipt/timeline metadata, draft messages, and notification mirrors are frequently in the clear even when the message store is not.

### Worked example A — WhatsApp (plain SQLite in an App Group)

The "easy" end of the spectrum and the most common request. WhatsApp keeps its core store *unencrypted at rest* (it relies on the iOS sandbox + Data Protection, not its own crypto), in the **Shared App Group**, not the Data container:

```
Containers/Shared/AppGroup/<UUID>/        # MCMMetadataIdentifier = group.net.whatsapp.WhatsApp.shared
├── ChatStorage.sqlite (+ -wal, -shm)     # the chat database  ← primary evidence
├── BackedUpKeyValue.sqlite               # account keys / owner identification material
├── Message/Media/                        # received & sent media, foldered by chat
│   └── <chat-jid>/<n>/<m>/<file>
└── ...
```

`ChatStorage.sqlite` is a **Core Data** store, so the table/column names are Core Data's mangled `Z`-prefixed form. The two tables you live in:

- **`ZWACHATSESSION`** — one row per conversation. `ZCONTACTJID` is the WhatsApp JID: `…@s.whatsapp.net` = a person, `…@g.us` = a group, `…@status` = a Status post. `ZSESSIONTYPE` encodes 0 = 1:1, 1 = group, 2 = broadcast, 3 = status. `ZPARTNERNAME` is the display name.
- **`ZWAMESSAGE`** — one row per message. `ZTEXT` = body; `ZFROMJID`/`ZTOJID` = endpoints; `ZISFROMME` = direction (0 in / 1 out); `ZMESSAGETYPE` = 0 text, 1 image, 2 video, 3 audio, 4 contact card, 5 location, 7 URL, 8 file (…and growing — verify against your version); `ZMESSAGEDATE` = the timestamp.
- **`ZWAMEDIAITEM`** — media metadata joined to `ZWAMESSAGE` by message PK; carries the on-disk relative path under `Message/Media/`, plus dimensions, lat/long for location messages, thumbnail blobs.

Three more places earn their keep once you're past the basic transcript:

- **`ZWAGROUPMEMBER`** / **`ZWAGROUPINFO`** (in `ChatStorage.sqlite`) — group rosters and group metadata; resolve who was *in* a group at the time, not just who spoke.
- **`ZWAMESSAGEINFO`** (in `ChatStorage.sqlite`) — per-recipient delivery/read receipts (and, for group messages, who read what when). This is the WhatsApp equivalent of Snapchat's receipt metadata: it survives even when content interpretation is contested, and it proves *awareness* and *timing*.
- **`ZWACDCALLEVENT`** / **`ZWACDCALLEVENTPARTICIPANT`** — the voice/video **call log**, which WhatsApp keeps in a *separate* `CallHistory.sqlite` in the **same App Group** (note the `CD` infix, and note it is **not** in `ChatStorage.sqlite`): direction, duration, and outcome, with its own Mac-Absolute timestamp. Investigators chasing "they never spoke" findings forget that the call history is this sibling DB — which is exactly why you enumerate the *whole* App Group, not just the chat store. *(Table names are version-volatile — confirm with `.tables` against `CallHistory.sqlite`.)*

`ZMESSAGEDATE` is **Core Data / Mac Absolute Time** — seconds since 2001-01-01 UTC — so add `978307200` to reach Unix epoch (the same constant you used for `knowledgeC` in [[01-knowledgec-db-deep-dive]]). Copy-before-query, then:

```sql
SELECT cs.ZPARTNERNAME                                             AS chat,
       m.ZISFROMME                                                AS from_me,
       datetime(m.ZMESSAGEDATE + 978307200,'unixepoch','localtime') AS sent,
       m.ZTEXT                                                    AS body,
       mi.ZMEDIALOCALPATH                                         AS media
FROM   ZWAMESSAGE m
JOIN   ZWACHATSESSION cs ON m.ZCHATSESSION = cs.Z_PK
LEFT JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = m.Z_PK
ORDER  BY m.ZMESSAGEDATE DESC LIMIT 50;
```

The method points to notice, not the column names: the *primary store was in the App Group*, the *epoch was Apple's 2001*, and *media lived as files on disk with the DB only holding paths* — three patterns you will re-meet in nearly every messenger.

### Worked example B — Signal (SQLCipher + GRDB, key in the Keychain)

The encrypted-messenger exemplar, and the reason "where's the key?" is its own step. Signal-iOS persists everything — messages, attachments metadata, contacts — in **one SQLCipher database** accessed through **GRDB** (a Swift SQLite wrapper), again in the **Shared App Group**:

```
Containers/Shared/AppGroup/<UUID>/grdb/
└── signal.sqlite (+ -wal, -shm)     # fingerprint: header is ENTROPY, not "SQLite format 3"
```

Step 3 fingerprints it instantly: it is named `.sqlite`, has WAL siblings, sits in a `grdb/` folder — context screams SQLite — yet `xxd | head` shows high-entropy bytes from offset 0. That mismatch = **SQLCipher**. Step 4: the key.

- Signal generates a random key once at first launch and stores it in the **Keychain** under the item `GRDBDatabaseCipherKeySpec` (base64 of the name: `R1JEQkRhdGFiYXNlQ2lwaGVyS2V5U3BlYw==`). In a decrypted Keychain dump (`keychain.plist`/`keychainDump.plist` from your FFS tool) the raw key bytes are the **base64-decoded `v_Data`** of that item.
- Decrypt off-device with the `sqlcipher` CLI. Modern Signal uses **SQLCipher 4** with a **plaintext header** (the salt is kept separate, so the file carries a 32-byte cleartext header before the ciphertext) — hence `cipher_plaintext_header_size = 32`. Older builds used SQLCipher 3 parameters. The robust recipe:

```sql
-- in `sqlcipher signal.sqlite`
PRAGMA key = "x'<64-hex-bytes-of-the-decoded-v_Data>'";
PRAGMA cipher_plaintext_header_size = 32;     -- SQLCipher 4 Signal builds
-- if it still won't open, it's an older build — add:
--   PRAGMA cipher_page_size = 1024;
--   PRAGMA cipher_hmac_algorithm   = HMAC_SHA1;
--   PRAGMA cipher_kdf_algorithm    = PBKDF2_HMAC_SHA1;
ATTACH DATABASE 'signal_plain.sqlite' AS plain KEY '';   -- empty key = no encryption
SELECT sqlcipher_export('plain');
DETACH DATABASE plain;
```

You now have a normal SQLite file (`signal_plain.sqlite`) to query with any tool. Note GRDB schemas evolved through major model migrations (the legacy `TSInteraction`/`TSThread`/`TSAttachment` tables vs. the newer normalized message/thread/attachment tables) — **verify the live schema with `.tables`/`.schema`; do not assume column names.** Signal timestamps are typically **Unix epoch in milliseconds** (divide by 1000 before `datetime(...,'unixepoch')`), a different epoch from WhatsApp's — exactly the kind of per-app variation [[00-the-ios-timestamp-zoo]] exists to catch.

There's a *second* layer of step 4 hiding here: decrypting `signal.sqlite` gets you the message text and metadata, but **the attachment files on disk are separately encrypted.** Signal writes each media file to the App Group in its own AES-encrypted blob; the per-file key (and an integrity digest) live in the *now-decrypted* attachment row, not in the Keychain. So the full pipeline is: Keychain key → decrypt DB → read each attachment's per-file key from the DB → decrypt that media file. Miss the second layer and you'll have a transcript that says "[photo]" with an undecryptable blob beside it. This nested-key pattern (a master key unlocks an index that holds per-item keys) recurs in well-built apps — recognize it.

> 🔬 **Forensics note:** The recoverability story is entirely about the key, not the DB. The `GRDBDatabaseCipherKeySpec` Keychain item is protected device-only (broadly an "after first unlock, this device only" posture), so it is **not** in an iTunes/Finder backup and **not** reachable on a BFU device. Translation: a logical backup of an iPhone yields `signal.sqlite` as undecryptable noise; you need a **full-filesystem acquisition with Keychain decryption on an AFU device** ([[07-decrypting-backups-and-images]], [[02-bfu-vs-afu-and-data-protection-classes]]). If all you have is a backup, Signal content is gone — *but its existence/activity* may still surface via Apple's own stores (notification text in [[13-notifications-keyboard-and-misc-stores]], app-usage intervals in [[01-knowledgec-db-deep-dive]]).

### Worked example C — Telegram (custom postbox + LevelDB + serialized blobs)

The "the schema is SQLite but the *data* isn't" case — and a reminder that "it's a SQLite file" doesn't mean "I can read it." Telegram keeps its store outside any backup, in the App Group:

```
Containers/Shared/AppGroup/<UUID>/telegram-data/
└── account-<id>/
    └── postbox/
        └── db/
            └── db_sqlite (+ -wal)     # SQLite *container*, opaque blob *contents*
```

`db_sqlite` is a genuine SQLite file (header reads `SQLite format 3`), but Telegram's **Postbox** layer uses it as a dumb **key/value store**: its tables are opaquely numbered (`t7` holds message records, `t2` holds chat/peer metadata, `t0` holds account settings — confirm with `.tables`, the numbering is an implementation detail) and each row's *value* is **Telegram's own serialized binary blob**, not columns you can `SELECT body FROM`. Opening it in `sqlite3` shows you keys and `BLOB`s — the message text is encoded *inside* the `t7` blob in Telegram's custom binary format (a hand-rolled coder, **not** protobuf). Parsing requires either community Postbox decoders (e.g. the `stek29` gist's reader, written for the macOS client but largely portable) or reversing the coder yourself. Telegram also keeps **LevelDB** stores elsewhere in `telegram-data/` for caches/state — a folder of `*.ldb`/`*.log` + `MANIFEST`/`CURRENT`, parsed with `ccl_leveldb`/`plyvel`.

The methodological lesson: step 3 has **two questions, not one** — "what's the container format?" *and* "what's the payload format inside it?" A SQLite file full of opaque blobs has only cleared the first. Note also Telegram's two-tier privacy: ordinary cloud chats are server-stored and present in `db_sqlite`; **Secret Chats** are device-only and E2E — recoverable only from the participating devices, and only while present.

### Worked example D — Snapchat (ephemerality ⇒ metadata outlives content)

The "designed to leave nothing" case, where the durable finding is *metadata about deletions*. Snapchat lives in the **Data** container (`/private/var/mobile/Containers/Data/Application/<UUID>/` for its bundle ID) and stores conversation/chat state in a SQLite store — historically `tcspahn.db`, later the `arroyo.db` chat store and an iOS `SCDB…`-prefixed conversation DB. *(Exact filenames vary by platform and version — fingerprint, don't assume; this is a verify-at-author-time detail.)*

The content (snaps, chats) is engineered to vanish after viewing. What survives:

- **Receipt metadata** — sent/delivered/opened/screenshotted timestamps per interaction persist in the chat DB long after the *content* is purged. You can frequently prove *that* A messaged B at time T, and that B opened or screenshotted it, with the message body itself gone.
- **WAL + freelist remnants.** "Clear Conversation" deletes rows from the live B-tree, but the bytes often linger in the `-wal` and in freelist pages of the main DB for days/weeks. Carving those ([[14-deleted-data-recovery]]) recovers records the UI swears are gone.
- **Caches** — Memories cache, `My Eyes Only` (an encrypted vault — its own step-4 key problem), and stray media in `Caches/`/`tmp/` at acquisition time.
- **Relationship & state stores** — the friends/contacts graph, per-friend `streak` counters, and any cached `bestFriends`/usernames survive purely as state, long outliving the conversations that built them. They establish *who knew whom* even when *what they said* is gone.
- **Location** — if the user enabled Snap Map, cached location/last-seen fragments may persist in the app's stores or in [[01-knowledgec-db-deep-dive]]-adjacent system caches; worth correlating against [[07-location-history]].

The standing rule for *any* "disappearing messages" app — Snapchat, Wickr, Telegram Secret Chats, disappearing-mode WhatsApp/Signal: treat the content as a bonus and the *metadata, caches, WAL/freelist, and Apple-side leakage* as the case. The app's own purge logic almost never reaches the notification mirror, the keyboard cache ([[13-notifications-keyboard-and-misc-stores]]), or the system thumbnail/usage stores.

> 🔬 **Forensics note:** With ephemeral apps, *invert your instinct*: stop chasing content and harvest **metadata + remnants**. The receipt timeline (delivered/opened/screenshot) is often more evidentially decisive than the message text — it proves contact, timing, and awareness. And because the WAL is where the un-checkpointed truth lives, the *single most destructive* mistake is letting any tool checkpoint or "helpfully repair" the DB before you've imaged main + `-wal` + `-shm`.

### Synthesis — what's durable vs. what rots

| Rots (re-verify every case) | Durable (the actual skill) |
|---|---|
| Table/column names (`ZWAMESSAGE`, `arroyo.db`) | "It's a Core Data store → `Z`-prefixed mangled names" |
| Exact Keychain item name | "Encrypted DB → key is almost certainly in the Keychain" |
| Which epoch a given app uses | "Always identify and normalize the epoch before believing a time" |
| Whether data is in Data vs App Group | "Enumerate *all* containers + every declared App Group" |
| SQLCipher version/PRAGMA values | "Entropy where a header belongs = encrypted; find the key, then decrypt" |
| The payload encoding (blob/protobuf) | "Container format and payload format are two separate questions" |

Memorize the right column. The left one is what reference docs and `--schema` dumps are for.

The four worked apps, on one line each — the *shape* of the answers the loop produces:

| App | Where (step 1–2) | Container format (step 3) | Payload | Key (step 4) | Epoch (step 6) |
|---|---|---|---|---|---|
| WhatsApp | Shared App Group | plain SQLite (Core Data) | columns | none (sandbox/DP only) | Mac Absolute, seconds |
| Signal | Shared App Group `grdb/` | **SQLCipher** | columns (after decrypt) | Keychain `GRDBDatabaseCipherKeySpec` + per-attachment keys in DB | Unix, **ms** |
| Telegram | Shared App Group `telegram-data/` | plain SQLite **+ LevelDB** | **serialized blobs** | none for cloud chats (Secret Chats device-only) | Unix, seconds (in blob) |
| Snapchat | Data container | plain SQLite | columns + ephemeral gaps | vault keys for My Eyes Only | Unix, **ms** |

Notice no two rows are identical across all five axes — which is exactly why a per-app "recipe" fails and the loop succeeds.

## Hands-on

All commands run **Mac-side** against a mounted FFS image, a public sample image, or a Simulator container — there is no on-device shell. Copy-before-query throughout.

**Fingerprint a directory of unknown stores** (steps 2–3 in one pass):

```bash
# Recursively classify every file by true type, not extension
find "<container>" -type f -print0 | xargs -0 file | sort

# Confirm a suspect DB by its header — the decisive 16 bytes
xxd "<container>/grdb/signal.sqlite" | head -1
#   plain SQLite  -> 0000: 5351 4c69 7465 2066 6f72 6d61 7420 3300  SQLite format 3.
#   SQLCipher     -> 0000: 9e3f 1c08 ...high entropy...            (no ASCII header)

# Find LevelDB stores (a directory, not a file)
find "<container>" -name CURRENT -o -name 'MANIFEST-*' | sed 's:/[^/]*$::' | sort -u
```

**Resolve a Simulator container UUID → bundle** (the device metadata plist has an exact analogue here):

```bash
# Every Data/Shared container carries the hidden mapping plist
plutil -p "<container>/.com.apple.mobile_container_manager.metadata.plist"
#   "MCMMetadataIdentifier" => "group.net.whatsapp.WhatsApp.shared"
```

**Parse plain SQLite safely** (WhatsApp, post-decryption Signal):

```bash
cp ChatStorage.sqlite{,-wal,-shm} /tmp/wa/        # take the WAL siblings too
sqlite3 /tmp/wa/ChatStorage.sqlite ".tables"      # learn the schema FIRST
sqlite3 /tmp/wa/ChatStorage.sqlite "SELECT name FROM sqlite_master WHERE type='table';"
```

**Decrypt a SQLCipher DB** with a key pulled from a Keychain dump:

```bash
# Recover the raw key from a decrypted keychain plist (FFS tools emit one)
KEY=$(plutil -extract '0.v_Data' raw -o - keychainDump.plist | base64 -D | xxd -p | tr -d '\n')
sqlcipher signal.sqlite <<SQL
PRAGMA key = "x'$KEY'";
PRAGMA cipher_plaintext_header_size = 32;
ATTACH DATABASE 'signal_plain.sqlite' AS plain KEY '';
SELECT sqlcipher_export('plain');
DETACH DATABASE plain;
SQL
sqlite3 signal_plain.sqlite ".tables"
```

**Decode an opaque blob / protobuf** (Telegram values, many config stores):

```bash
# Pull one blob out, then try a schema-less protobuf decode
sqlite3 db_sqlite "SELECT quote(value) FROM t7 LIMIT 1;"   # t7 = Telegram message records; inspect raw bytes
protoc --decode_raw < blob.bin                              # field-numbered tree, no .proto needed
#   NB: Telegram's Postbox coder is NOT protobuf, so --decode_raw will mostly choke on a t7 blob —
#   that negative result IS the lesson: you need a Postbox decoder (stek29's reader), not a generic
#   protobuf tool. --decode_raw is the right reflex for the *many other* apps whose blobs are protobuf.
# or, in Python:  import blackboxprotobuf; blackboxprotobuf.decode_message(open('blob.bin','rb').read())
```

**Hunt for an on-disk key** (the step-4 fast path before you reach for a Keychain dump):

```bash
# Likely key names in NSUserDefaults and config plists
plutil -p "<container>/Library/Preferences/"*.plist | grep -iE 'key|secret|cipher|token|pass'
# High-entropy base64-looking values anywhere in the container (candidate raw keys)
grep -raoE '[A-Za-z0-9+/]{43,}={0,2}' "<container>" | sort -u | head
# Strings in the app binary — weak apps hardcode/obfuscate keys here
strings -a "<UUID>/<App>.app/<App>" | grep -iE 'key=|secret|AES'
```

**Crack open a Realm and a LevelDB** (the non-SQL stores):

```bash
# Realm: confirm it is NOT SQLite, then open with Realm Studio (GUI) or the SDK
file default.realm                      # "Realm file" — sqlite3 will refuse it
# LevelDB / IndexedDB: a folder, parsed by record (ccl_leveldb.py ships in CCL's ccl_chromium_reader repo)
python3 ccl_leveldb.py "<container>/Library/.../IndexedDB/..._0.indexeddb.leveldb"
```

**Let a parser do the boring 80%** — iLEAPP ships modules for many third-party apps and runs on an extracted file tree on the Mac:

```bash
git clone https://github.com/abrignoni/iLEAPP && cd iLEAPP   # runs from source — there is no `pip install ileapp`
pip3 install -r requirements.txt
python ileapp.py -t fs -i /path/to/extracted_filesystem -o /tmp/ileapp_out   # HTML+SQLite report; -t = fs|zip|tar|gz
# Triage with iLEAPP, then hand-parse the long tail it doesn't cover.
```

## 🧪 Labs

> All labs are **device-free**. They build the format-recognition reflex on substrates that faithfully reproduce *structure and parsing*. **Fidelity caveat:** the Simulator runs macOS frameworks — **no Data Protection, no SEP, and the Keychain is a Mac-side file, so nothing here demonstrates real key-extraction gating** (BFU/AFU, protection classes). Encryption/lock-state behavior is taught on sample images and the self-built SQLCipher lab, never inferred from the Simulator.

### Lab 1 — Resolve & inventory a container (Simulator)

Substrate: Xcode Simulator. *Caveat: container layout is identical to a device, but paths are unencrypted on your Mac and there is no App-Group key gating.*

1. Boot a Simulator and install/launch a couple of apps (Notes, Safari, or any free App Store-free sample app you can build), generating data.
2. Find the data root:
   ```bash
   xcrun simctl get_app_container booted com.apple.mobilenotes data   # prints the Data container path
   open "$(xcrun simctl get_app_container booted com.apple.mobilenotes data)"
   ```
3. From a *bare UUID* folder under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/`, run step 1 yourself: `plutil -p .../.com.apple.mobile_container_manager.metadata.plist` and confirm `MCMMetadataIdentifier`. You've just done UUID→bundle resolution without the convenience command.
4. Inventory: `find . -type f | xargs file | sort`. List every store and its real format. Note which live in `Documents/` vs `Library/Application Support/` vs `Caches/`.

### Lab 2 — Format triage by magic bytes (any files)

Substrate: read-only walkthrough on files you create. *Caveat: pure parsing drill; no acquisition realism.*

1. Make one of each: a SQLite DB (`sqlite3 t.db 'create table x(a);'`), a binary plist (`plutil -convert binary1 -o t.plist <(echo '{"k":1}' | plutil -convert xml1 -o - -)`), and a protobuf blob (any `.bin` you have).
2. Rename them all to `.dat`. Now identify each by header alone: `for f in *.dat; do echo "== $f"; xxd "$f" | head -1; done`.
3. Verify with `file *.dat`. You should be able to call SQLite (`SQLite format 3`), bplist (`bplist00`), and "structured-but-headerless" (protobuf) on sight. This is step 3 at speed.

### Lab 3 — Decrypt a SQLCipher database (self-built Signal stand-in)

Substrate: a SQLCipher DB you build on the Mac. *Caveat: the key sits in a file you made, not a real iOS Keychain — this exercises the **decryption** half of step 4/5 faithfully, but **not** the device key-extraction gating (do that against a sample image in Lab 5).* 

1. `brew install sqlcipher`. Create an encrypted DB and seed it:
   ```bash
   sqlcipher secret.db "PRAGMA key='hunter2-as-passphrase';
     CREATE TABLE msg(id INTEGER, body TEXT, ts INTEGER);
     INSERT INTO msg VALUES(1,'meet at the pier',1750000000000);"
   ```
2. Prove it's opaque: `xxd secret.db | head -1` — no `SQLite format 3`. Confirm `sqlite3 secret.db .tables` **fails** (plain SQLite can't read it).
3. Decrypt with the recipe (`PRAGMA key` → `sqlcipher_export`) into `plain.db`; query it with plain `sqlite3`. Convert the millisecond timestamp: `SELECT datetime(ts/1000,'unixepoch')`. You've reproduced the Signal decrypt path end to end.

### Lab 4 — Recover deleted rows from a WAL (read-only walkthrough)

Substrate: a SQLite DB you mutate. *Caveat: demonstrates the WAL-remnant mechanism that makes ephemeral-app recovery possible; not a full carve.*

1. Create `c.db`, set `PRAGMA journal_mode=WAL;`, insert 5 "messages," then `DELETE` three of them — **without** checkpointing (don't run `wal_checkpoint`, don't cleanly close in a way that truncates the WAL).
2. Copy `c.db`, `c.db-wal`, `c.db-shm` together to `/tmp`. Inspect the WAL: `strings c.db-wal` — observe the "deleted" bodies still present in WAL frames.
3. Internalize: querying the DB *with* its WAL present can checkpoint and erase exactly this evidence. This is why copy-before-query takes the siblings.

### Lab 5 — End-to-end on a public sample image (WhatsApp/Signal)

Substrate: Josh Hickman's iOS reference image (thebinaryhick.blog / Digital Corpora) or the iLEAPP test data. *Caveat: a real device image — exercises container resolution, App-Group discovery, and (for Signal) the key-in-Keychain dependency that the Simulator cannot.*

1. Mount/extract the image. Run `python ileapp.py -t fs -i <root> -o /tmp/out` and open the report; locate the WhatsApp section.
2. Then *by hand*: navigate to `Containers/Shared/AppGroup/<UUID>/`, confirm `MCMMetadataIdentifier = group.net.whatsapp.WhatsApp.shared`, copy `ChatStorage.sqlite` + WAL, and run the join query from Worked Example A. Compare your output to iLEAPP's — understanding *why* they match is the point.
3. If the image contains Signal + a Keychain dump, find `grdb/signal.sqlite`, fingerprint it as SQLCipher, locate `GRDBDatabaseCipherKeySpec` in the keychain plist, and decrypt. If the image has the DB but **no** Keychain, document *why it's unrecoverable* — that conclusion is itself the deliverable.

### Lab 6 — Parse a non-SQL store (LevelDB/IndexedDB)

Substrate: a LevelDB you generate via Chrome on your Mac, or a sample app's WebKit storage from a Simulator. *Caveat: exercises the LevelDB+serialized-payload "two-format" parse; the on-disk layout matches an iOS hybrid app's WebKit IndexedDB store.*

1. In Chrome, open any site that uses IndexedDB (or a tiny local page that calls `indexedDB.open(...)` and `put`s a record). Then locate the store: `~/Library/Application Support/Google/Chrome/Default/IndexedDB/<origin>.indexeddb.leveldb/`. Confirm it's a *folder* with `CURRENT` + `MANIFEST-*` + `*.ldb`/`*.log`.
2. Clone CCL's `ccl_chromium_reader` repo (Caithness; the LevelDB module is `ccl_leveldb.py`, formerly distributed as `ccl_chrome_indexeddb`) and dump the raw key/value records: `python3 ccl_leveldb.py <path>`. Observe that the *keys* are structured and the *values* are serialized blobs — the container is parsed, the payload is not yet.
3. Run the IndexedDB reader from `ccl_chromium_reader` over the same folder to decode the WebKit/Chromium serialization on top, yielding readable objects. You've now descended both layers — exactly the skill Telegram's Postbox and any blob-in-SQLite store demands.

## Pitfalls & gotchas

- **Trusting the extension.** A `.db` may be SQLCipher; a `.sqlite` may be Realm; a `.dat` may be a bplist. Always `xxd | head` and `file`. The header is law.
- **Forgetting the WAL/SHM.** Copying only the main DB silently drops deleted/edited/in-flight rows and risks a checkpoint that destroys them. Copy `db` + `-wal` + `-shm`, and image before querying.
- **Querying only the Data container.** Messengers hide the real DB in the **Shared App Group**. Enumerate every container *and* every App Group the bundle declares (read its entitlements).
- **Assuming one epoch.** WhatsApp = Mac Absolute (2001, seconds). Signal/Snapchat = Unix **milliseconds**. Telegram = Unix seconds inside a blob. Mixing them puts events 31 years or 1000× off. Identify the epoch per store; see [[00-the-ios-timestamp-zoo]].
- **"It's SQLite, so I can read it."** Telegram's `db_sqlite` is SQLite holding opaque serialized blobs; you've parsed the *container*, not the *payload*. Two formats, two steps.
- **Treating an encrypted DB as recoverable from a backup.** If the key is a device-only Keychain item, a logical/iTunes backup gives you ciphertext only. You need FFS + Keychain + an AFU device. Don't promise content you can't decrypt.
- **Checkpointing/"repairing" before imaging.** Tools that auto-checkpoint or run `PRAGMA integrity_check` with write access can destroy freelist/WAL remnants — the exact bytes that recover deleted ephemeral messages. Work on copies; mount read-only.
- **Stale schema memory.** Apps re-key, migrate tables, and move files between releases. `.schema`/`.tables` first, every case — never paste last year's query and trust the column names.
- **Reinstall containers.** Multiple UUID containers for one bundle ID = reinstall(s). The orphaned container is a "before" snapshot; don't analyze only the live one.
- **Dismissing a LevelDB folder as cache.** A directory holding `CURRENT` + `MANIFEST-*` + `*.ldb` is a database, not junk — and for hybrid/web-view apps it's often the *only* place the data lives. `file` a folder gives you nothing; recognize the layout.
- **Local time vs UTC.** Apple stores epochs in UTC; analysts display in local time. State your conversion (`'localtime'` vs not) in every report and pin the device's timezone from a system source — a silent UTC/local mix is a classic timeline error and a defense gift.
- **Trusting a tool's "no data" for an app it doesn't support.** A commercial suite returning zero rows for an unknown app means *it has no parser*, not that the app has no data. Verify by hand-walking the container before you write "no artifacts present."

## Key takeaways

- The skill is the **six-step loop** — resolve → inventory → fingerprint → key → parse → timestamp — not any one app's schema. Apply it to the app nobody has reversed yet.
- iOS files third-party data under **opaque UUIDs**; resolve UUID→bundle via the per-container `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`), cross-checked with `applicationState.db` and the MobileInstallation maps.
- **Fingerprint by magic bytes, never extension.** `SQLite format 3` vs `bplist00` vs entropy-from-byte-0 (encrypted) vs a folder of `*.ldb` (LevelDB) vs headerless field-tags (protobuf).
- For encrypted apps, **the key is the case** — almost always a Keychain item, and its **Data Protection class** (not the DB's) decides whether the data survives a backup and whether you need an AFU FFS acquisition.
- WhatsApp = plain SQLite (Core Data) in an App Group; **Signal = SQLCipher whose key is `GRDBDatabaseCipherKeySpec` in the Keychain**; Telegram = SQLite-container-of-opaque-blobs + LevelDB; Snapchat = ephemeral, so **metadata and WAL/freelist remnants outlive content**.
- Always copy **main + `-wal` + `-shm`** and work on copies; the WAL/freelist is where deleted and edited messages live.
- Container format and payload format are **two separate questions** — a SQLite file full of serialized blobs is only half-parsed.
- Triage with iLEAPP/mac_apt, then hand-parse the long tail they don't cover — which is exactly where the decisive evidence usually is.

## Terms introduced

| Term | Definition |
|---|---|
| App Group container | Shared sandbox (`Containers/Shared/AppGroup/<UUID>/`) reachable by an app and its extensions; where messengers usually hide the real DB |
| `MCMMetadataIdentifier` | Key in a container's `.com.apple.mobile_container_manager.metadata.plist` giving the bundle ID (Data) or App Group ID (Shared) — the UUID→bundle ground truth |
| `applicationState.db` | SQLite at `/var/mobile/Library/FrontBoard/applicationState.db` mapping bundle IDs to container UUIDs and run state |
| Magic bytes | The first bytes of a file that identify its true format regardless of extension (`SQLite format 3`, `bplist00`, …) |
| SQLCipher | Transparent AES-256 encryption layer over SQLite; the file is entropy from byte 0 and needs a key (`PRAGMA key`) to open |
| GRDB | Swift SQLite toolkit Signal-iOS uses; pairs with SQLCipher for the encrypted message store |
| `GRDBDatabaseCipherKeySpec` | The iOS Keychain item holding Signal's random SQLCipher key (raw bytes = base64-decoded `v_Data`) |
| `cipher_plaintext_header_size` | SQLCipher 4 PRAGMA for DBs (like Signal) that keep a cleartext header so the salt lives outside the file (value 32) |
| `sqlcipher_export` | SQLCipher function that copies a decrypted DB into a plain attached database for analysis |
| Postbox | Telegram's custom key/value persistence layer over a SQLite file (`db_sqlite`) storing serialized binary blobs, not columns |
| LevelDB | Google's on-disk key/value store (a directory of `*.ldb`/`*.log` + `MANIFEST`/`CURRENT`); common for caches/state |
| IndexedDB | Web-storage API; on iOS a WKWebView app persists it as LevelDB holding WebKit/Chromium-serialized objects (a two-format store) |
| Realm | Object database (not SQLite) with its own header; encrypted variants use a 64-byte AES+HMAC key, usually parked in the Keychain |
| WAL (`-wal`) | SQLite write-ahead log holding committed-but-uncheckpointed rows; frequently retains deleted/edited messages |
| Core Data / Mac Absolute Time | Apple's `Z`-prefixed object store; timestamps are seconds since 2001-01-01 (add 978307200 for Unix epoch) |
| Receipt metadata | sent/delivered/opened/screenshot timestamps that persist after ephemeral content is purged |

## Further reading

- Apple — *App Distribution / App Sandbox*, *Keychain Services*, and Data Protection in the Apple Platform Security guide (key protection classes that gate extraction).
- Alexis Brignoni — **iLEAPP** (`github.com/abrignoni/iLEAPP`); the de-facto open third-party-app parser and a living catalog of current schemas.
- Yogesh Khatri — **mac_apt** / `ios_apt` (`github.com/ydkhatri/mac_apt`) for image-level batch parsing.
- Alex Caithness / CCL Solutions — **`ccl_leveldb`**, `ccl_bplist`, and protobuf/SimpleSnappy tooling; the reference for LevelDB and Apple-blob payloads.
- **SQLCipher** docs (zetetic.net) — PRAGMA semantics, cipher versions 3↔4, plaintext-header config; **GRDB** docs (`github.com/groue/GRDB.swift`).
- Magpol — *HowTo-decrypt-Signal.sqlite-for-iOS* (`github.com/Magpol/HowTo-decrypt-Signal.sqlite-for-IOS`); the keychain-key + PRAGMA recipe.
- kacos2000 — *Queries* repo (`github.com/kacos2000/Queries`), incl. a maintained `WhatsApp_Chatstorage_sqlite.sql`.
- Group-IB / Belkasoft / Magnet — WhatsApp, Telegram, and Snapchat iOS artifact profiles (current schema walkthroughs; treat as version-stamped).
- `blackboxprotobuf` (`github.com/nccgroup/blackboxprotobuf`) and `protoc --decode_raw` — schema-less protobuf decoding.
- Josh Hickman — iOS reference images (thebinaryhick.blog / Digital Corpora); SANS **FOR585** (Smartphone Forensics) for the broader app-by-app methodology.
- `man sqlite3`, `man file`, `man plutil`, `xcrun simctl help`.

---
*Related lessons: [[00-app-sandbox-and-filesystem-layout]] | [[04-communications-imessage-and-sms]] | [[08-keychain-on-ios]] | [[14-deleted-data-recovery]] | [[00-the-ios-timestamp-zoo]] | [[07-decrypting-backups-and-images]] | [[05-full-file-system-acquisition]] | [[05-dynamic-analysis-with-frida]]*
