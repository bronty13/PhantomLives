---
title: "Notifications, keyboard & misc stores"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 13
est_time: "45 min read + 20 min labs"
prerequisites: [app-sandbox-and-filesystem-layout]
tags: [ios, forensics, notifications, keyboard, accounts, dfir]
last_reviewed: 2026-06-26
---

# Notifications, keyboard & misc stores

> **In one sentence:** The highest-yield evidence on a "wiped" iPhone often lives nowhere near the app that produced it — full message previews persist in the notification store after the chat is deleted, every word the user has ever typed accretes in a proprietary keyboard lexicon that behaves like a partial keylog, and the Accounts database, pasteboard, and a few dozen `com.apple.*` preference plists quietly catalogue identities and device state that the user never knowingly saved.

## Why this matters

Picture the case that defines this lesson: a suspect ran an encrypted messenger, deleted the app, and reset the phone's Messages and Safari. The chat database is gone, the container is unrecoverable, the browser history is empty. And yet — the Lock Screen preview of the last message sits in a `DeliveredNotifications.plist`, the contact's name was typed often enough to be in the keyboard lexicon, the messenger's account is still listed in `Accounts3.sqlite` with the date it was added, and the copied wallet address is still on the pasteboard. The "deleted" conversation is reconstructable from four stores the suspect never knew existed. That is the entire thesis.

Investigators spend most of their time on the primary stores — `sms.db`, `CallHistory.storedata`, `Photos.sqlite`, `History.db`. The trouble is those are exactly the stores a guilty or privacy-conscious user clears. What survives is the *spill*: the OS-level scaffolding that copied the data sideways for its own convenience and never garbage-collected it. A delivered iMessage preview sits in a `DeliveredNotifications.plist` long after the message row is gone. A password typed once into a login form gets ingested into the keyboard's learning model and surfaces in a flat binary blob years later. The Accounts database records the *enable date* of a Gmail account the user swears they never configured. None of these are "the evidence" the suspect thought to delete — which is precisely why they are the evidence. This lesson maps the secondary and tertiary stores: where they live, the format, the daemon that writes them, the timestamp epoch, and the deletion-survival property that makes each one matter.

## Concepts

### The displacement principle

Every store in this lesson exists because iOS *copies user content out of the originating app* for a system purpose — to render a banner, to power predictive text, to authenticate a sync session, to share a clipboard across apps. The copy lives in a system-owned location with its own retention policy, decoupled from the app's own database. When the user (or an app's "delete forever") nukes the primary store, the displaced copy is untouched. Three properties make a displaced store forensically valuable:

1. **Different sandbox owner** — it's in `/var/mobile/Library/...` (system/`mobile`-owned), not in the app's `Data` container, so app-level "clear history" never reaches it.
2. **Lazy or absent garbage collection** — the OS rarely prunes these aggressively; the keyboard lexicon and pasteboard in particular accrete or hold "last value" indefinitely.
3. **Content, not just metadata** — unlike `knowledgeC`/Biome which mostly log *that* something happened, these stores frequently hold the actual *text* (the message body, the typed word, the copied string).

```
 App's own store (cleared/deleted)            System displaced copy (survives)
 ──────────────────────────────────           ─────────────────────────────────
 Messages → sms.db row deleted        ──────▶ UserNotifications/<bundle>/DeliveredNotifications.plist
 anything typed in any text field     ──────▶ Keyboard/<lang>-dynamic-text.dat  (learned lexicon)
 account removed in Settings          ──────▶ Accounts/Accounts3.sqlite ZACCOUNT (enable date lingers)
 copied text                          ──────▶ pasteboardd general pasteboard (last value held)
 app setting toggled                  ──────▶ Preferences/com.apple.<x>.plist (cfprefsd-managed)
```

> 🔬 **Forensics note:** The corroboration play is the point. A deleted message recovered from `DeliveredNotifications.plist` is strong on its own, but pair it with the same sender appearing in `interactionC.db`, the same string fragment in the keyboard lexicon, and a matching `knowledgeC` `/notification/usage` interval, and you have four independent stores agreeing — far harder to attack than any single recovered row.

---

### The notification store — full message previews after deletion

iOS keeps the notifications it has *delivered* (sitting on the Lock Screen / in Notification Center) as on-disk files per app. The path is system-owned:

```
/private/var/mobile/Library/UserNotifications/<bundle-id-or-GUID>/
    DeliveredNotifications.plist     ← the body: title, subtitle, message text, sender, timestamps
    AttachmentList.plist             ← image/media attachments referenced by the notifications
    Attachments/                     ← the actual cached attachment files
```

Each subdirectory is keyed by the app's bundle identifier (some iOS versions/tooling surface it as a GUID that resolves back to the bundle). The store is written by the **system notification pipeline** — the **`UserNotificationsServer`** process together with SpringBoard's **BulletinBoard** layer (with `apsd`, the Apple Push Service daemon, handling the push transport) — *not* by the app, which is why an app's own "delete chat" never touches it. (The exact internal process/daemon names are undocumented and drift across iOS versions; `UserNotificationsServer` and `BulletinBoard` are the names that surface in the unified log writing this tree — don't hang an argument on a specific daemon name, hang it on the on-disk path.)

**Format.** `DeliveredNotifications.plist` and `AttachmentList.plist` are **`NSKeyedArchiver`-serialized binary plists**, not flat key/value plists. You cannot just `plutil -p` them and read the body — you get a `$objects`/`$top`/`$objref` object graph that must be *deserialized* (walk the `$objref` integer pointers back into the `$objects` array). The interesting payload is the notification's `request` → `content`, whose `title`, `subtitle`, `body`, and `threadIdentifier` carry the human-readable text, plus `date`/delivery timestamps stored as `NSDate` (Mac/Cocoa absolute time — seconds since **2001-01-01**, add **978307200** for Unix epoch).

```
NSKeyedArchiver graph — why plutil shows nothing useful
┌─────────────────────────────────────────────────────────────┐
│ $top   : { root: <CF$UID 1> }            ← entry pointer      │
│ $objects[0] = "$null"                                         │
│ $objects[1] = { request: <UID 2>, date: <UID 7>, ... }       │
│ $objects[2] = { content: <UID 3> }                           │
│ $objects[3] = { title: <UID 4>, body: <UID 5>, ... }         │
│ $objects[4] = "Mom"                       ← the actual text   │
│ $objects[5] = "call me when you land"     ← the actual body  │
│ $objects[7] = NSDate 7.6e8 (Mac abs time) ← delivery time    │
└─────────────────────────────────────────────────────────────┘
 plutil -p prints this raw array; the deserializer follows the
 <UID> pointers to reassemble {title:"Mom", body:"call me..."}.
```

**Attachments survive too.** `AttachmentList.plist` (also `NSKeyedArchiver`) enumerates media tied to each notification, and the `Attachments/` subfolder holds the **cached attachment files themselves** — the thumbnail/image that rode along with a rich notification. A picture pushed in a notification can therefore persist on disk after the originating message and its in-app media are gone. Carve `Attachments/` for orphaned media even when the plists have been pruned.

**Why it's gold:** the banner that flashed on the Lock Screen contains, for a messaging app, the **sender name and a preview (often the full text) of the message** — even if the user later deleted the message in-app, even if the app's database was cleared, even if the message was a "view once" / disappearing message. For social and dating apps the preview frequently includes the match/contact name and the opening line. The notification is the system's copy of content the app never persisted in recoverable form.

**Communication notifications enrich the payload.** Since iOS 15, messaging apps adopt **communication notifications** (donating an `INSendMessageIntent` so the banner shows the contact's name and avatar). That intent data rides into the delivered-notification archive, so the recovered plist can carry not just the body but a **resolved sender identity** (display name, sometimes a handle and an avatar reference) richer than a bare push payload. For a third-party messenger that stores conversations encrypted in its own container, this enriched notification copy may be the cleanest place the sender's human-readable name appears in plaintext on the device.

**Companion streams.** The same notification activity is *also* logged in two pattern-of-life stores you met earlier:

- `knowledgeC.db` records a `/notification/usage` stream (in `ZOBJECT`, with per-notification metadata in `ZSTRUCTUREDMETADATA`) — *that* a notification for bundle X was delivered/interacted-with at time T (metadata, usually no body). See [[knowledgec-db-deep-dive]].
- The DuetExpertCenter / Biome SEGB stream `userNotificationEvents` (`/private/var/mobile/Library/DuetExpertCenter/streams/userNotificationEvents/` and the iOS 17+ Biome equivalent) logs delivery/dismissal events as SEGB records. See [[biome-and-segb-streams]].

So the play is: **bodies** from `UserNotifications/*.plist`, **timeline of delivery/interaction** from `knowledgeC` + the SEGB stream. They cross-validate.

> 🖥️ **macOS contrast:** On the Mac you parsed the Notification Center database — `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (a single SQLite written by `usernoted`, with a `record` table of `NSKeyedArchiver` blobs). iOS made a different design choice: **per-app `NSKeyedArchiver` plists** under `UserNotifications/`, not one central SQLite. Same "delivered notification body survives deletion" payoff, different container — so don't go hunting for a `usernoted` db on the iPhone; hunt the per-bundle plist tree.

> 🔬 **Forensics note:** `iLEAPP` parses this tree directly (its notifications module deserializes the `NSKeyedArchiver` graph for you). For ad-hoc work use a deserializer — Alex Caithness's `ccl_bplist`, the `nska_deserialize` helper, or `mac_apt`'s notification plugin. Treat the plists as evidence files: copy them out first, deserialize on a copy, and record the original mtimes — the store is rewritten as notifications are cleared, so a current acquisition is a *snapshot*, and an earlier full-file-system image or backup may hold notifications since cleared.

---

### The keyboard learned lexicon — a partial keylog

This is the artifact with **no clean macOS equivalent** and the one that most often catches investigators (and suspects) by surprise. iOS's autocorrect/predictive-text engine *learns the words you type* — proper nouns, slang, usernames, street names, and, notoriously, things typed into fields the user assumed were private — and accretes them into proprietary files under:

```
/private/var/mobile/Library/Keyboard/
    dynamic-text.dat                  ← the learned-lexicon blob (legacy single-file name)
    <lang>-dynamic-text.dat           ← per-language variants on modern iOS, e.g. en_US-dynamic-text.dat
    user_model_database.sqlite        ← newer learning store (typing/model data)
    shapestore.db                     ← swipe-to-type (QuickPath) gesture/shape store
    UserDictionary.sqlite             ← user-defined text replacements / shortcuts
    CloudUserDictionary.sqlite        ← the iCloud-synced version of the above
```

> ⚠️ Flag for verification at author time: the **exact filename convention** has drifted. The classic artifact is a single `dynamic-text.dat`; modern iOS ships **per-language** files named `<lang>-dynamic-text.dat` (e.g. `en_US-dynamic-text.dat`) alongside the SQLite learning stores. Confirm the precise names against your sample image / acquisition rather than assuming — the *mechanism* (a binary lexicon that accretes typed words per keyboard language) is durable; the filenames are version-specific.

**Mechanism.** As you type, the keyboard ingests novel words into a learning model so it can predict and autocorrect them later. There is **one lexicon per configured keyboard language** (hence the per-language filenames). Words are added roughly in the order they were first typed and across **every app** — Messages, Notes, Safari address bar, search fields, and (the dangerous part) sometimes text the user pasted or typed into less-guarded fields. Apple excludes secure-text-entry (password) fields *by design* — but real-world acquisitions routinely show that **passwords, full names, email addresses, physical addresses, and slang still land in the lexicon**, because they were typed into a non-secure field at some point (a username box, a "show password" toggle, a note, a search). The classic file historically held on the order of a few hundred words per language.

**Format.** `dynamic-text.dat` is an **undocumented binary blob**, not a database — you read it with a hex editor or, for triage, by carving printable strings:

```bash
strings -a /path/to/en_US-dynamic-text.dat        # quick word dump (UTF-8 runs)
strings -e l /path/to/en_US-dynamic-text.dat       # also catch UTF-16LE runs
```

Because words are laid down roughly **sequentially**, fragments of the dump can read like a skeleton of conversations and credentials in typing order — which is what earns it the "near-keylog" label. The newer `user_model_database.sqlite` is queryable SQLite (richer, model-oriented); `UserDictionary.sqlite` / `CloudUserDictionary.sqlite` hold the user's explicit text-replacement shortcuts. `iLEAPP` has a keyboard/dynamic-dictionary module that parses these.

**The QuickType learning model.** The lexicon is one face of the broader QuickType engine. As autocorrect, predictive bar, and (since iOS 13) **swipe-to-type / QuickPath** all feed the same learning pipeline, the on-disk model accretes not just isolated words but *n-gram* associations — which words the user types after which. That is why a lexicon dump can surface multi-word phrases and not only single tokens. Swipe-to-type (QuickPath), importantly, still feeds the same learning pipeline — and writes its own companion artifact, `shapestore.db`, in the Keyboard directory — so a user who "only swipes" is not exempt; carve `shapestore.db` alongside the lexicon. On iOS 26, the on-device Apple-Intelligence writing/prediction stack adds further model state under the keyboard and intelligence directories; ⚠️ the exact iOS 26 Apple-Intelligence keyboard artifact paths are still being characterized by the community — treat any specific path you find as provisional and verify against your image rather than citing it as settled.

> 🖥️ **macOS contrast:** macOS *has* keyboard text replacements (`~/Library/KeyboardServices/TextReplacements.db`) and a global typing data store, but it has **no accreting per-language learned-lexicon blob** that silently captures everything you've ever typed the way iOS's `dynamic-text.dat` does. This is one of the few iOS artifacts with materially *more* investigative reach than its Mac counterpart — on the Mac you'd reach for the Unified Log or app stores; on iOS the keyboard itself is a passive recorder.

> 🔬 **Forensics note:** This is frequently the *only* surviving source. A suspect deletes a chat app, wipes its container, and clears Messages — but the names, the burner-app username, the wallet seed phrase fragment, the address typed into a maps search are still in the lexicon. Because the file is small and flat, it survives backups cleanly and is trivial to triage (`strings`) even before full parsing. Treat hits as *leads* needing corroboration (the lexicon does not timestamp individual words or tie them to an app), not as standalone proof of a specific message.

---

### Accounts — every configured identity, with enable dates

Every account the user configures — iCloud, Google, Exchange, Yahoo, Twitter/X, Facebook, LinkedIn, the account behind each Mail/Calendar/Contacts source, app-specific accounts — is registered with the **Accounts framework (ACAccount)** and persisted in a single SQLite database:

```
/private/var/mobile/Library/Accounts/Accounts3.sqlite
```

(`Accounts3.sqlite` is the long-standing iOS filename; the macOS/desktop lineage advanced to `Accounts4.sqlite`. On a given image, check for whichever exists — the schema is the same family.)

**Schema (Core Data-style, `Z`-prefixed):**

| Table | What it holds |
|---|---|
| `ZACCOUNT` | One row per configured account: `ZUSERNAME`, `ZIDENTIFIER` (GUID), `ZACCOUNTDESCRIPTION`, `ZDATE` (add/enable time), `ZACTIVE`/`ZENABLED`, `ZOWNINGBUNDLEID` |
| `ZACCOUNTTYPE` | The account *kind*: `ZACCOUNTTYPEDESCRIPTION` (e.g. "iCloud", "Google", "Exchange"), `ZIDENTIFIER` (e.g. `com.apple.account.Google`) |
| `ZACCOUNTPROPERTY` | Key/value extras hung off an account (server hostnames, capability flags, identifiers) |
| `ZDATACLASS` | Which data classes the account syncs (Mail, Contacts, Calendars, Bookmarks, Notes…) |

You join `ZACCOUNT.ZACCOUNTTYPE` → `ZACCOUNTTYPE.Z_PK` to label each account by service. `ZDATE` is the high-value column: it is a **Mac/Cocoa absolute timestamp** (epoch 2001-01-01; add 978307200) recording when the account was added/enabled — i.e. *when the user first signed that identity into the device*. ⚠️ Confirm the exact date column name and semantics on your target version (Core Data column naming and the add-vs-modify distinction shift between releases).

**Parent/child accounts and data classes.** One sign-in often spawns *several* `ZACCOUNT` rows: a top-level identity (e.g. the iCloud or Google account) plus child accounts for each sync service it provides (Mail, Contacts, Calendars, Notes, Bookmarks). `ZACCOUNT.ZPARENTACCOUNT` links a child back to its parent, and `ZDATACLASS` enumerates which data classes are active — so the database tells you not just *that* a Google account exists but that **Contacts and Calendar sync were enabled** for it. That distinction matters when you're arguing whether contacts on the device originated locally or synced from a cloud identity. `ZACCOUNTPROPERTY` rows hang server hostnames and capability flags off the account, occasionally revealing the mail server or the exact service endpoint.

> 🖥️ **macOS contrast:** This is the *same database family* you already know — on the Mac it's `~/Library/Accounts/Accounts4.sqlite`, identical `ZACCOUNT`/`ZACCOUNTTYPE` shape. The Accounts framework is shared across platforms, so the skill transfers verbatim; only the filename digit and the path prefix differ.

> 🔬 **Forensics note:** Beyond "what services does this person use," the `ZIDENTIFIER` GUIDs are **join keys**. Other stores reference an account by its Accounts GUID — e.g. `interactionC.db` (contacts/interactions) ties communications to the account that handled them. Pulling the GUID→service mapping out of `Accounts3.sqlite` first lets you resolve those foreign keys everywhere else. The enable date is also an anti-deception anchor: a Google account with a `ZDATE` of two years ago contradicts "I just got this phone last week."

---

### The pasteboard (clipboard)

iOS's system clipboard is the **general pasteboard** (`UIPasteboard.general`, identifier `com.apple.UIKit.pboard.general`), brokered by the **`pasteboardd`** daemon. Two properties matter forensically:

- The general pasteboard is **persistent across reboots and even app uninstalls** — it holds the *last copied value* until something overwrites it.
- Until iOS hardened it, **any app could read the pasteboard with no permission**; iOS 14+ shows the "pasted from…" banner and gates programmatic access, but the *content itself* is still resident.

So a live or recently-quiesced acquisition can yield the **last thing the user copied** — frequently a password, a 2FA code, a crypto address, a URL, or a snippet of a message. Pasteboard items are typed (UTI-tagged): `public.utf8-plain-text`, `public.url`, `public.png`, etc.

> ⚠️ Flag for verification: the **exact on-disk persistence path** for `pasteboardd` is version-specific and not cleanly documented — caches have historically appeared under `/private/var/mobile/Library/Caches/` in `pasteboard`-related directories. Do **not** quote a fixed path as fact; confirm against your image. On Apple Silicon Macs you can also reach the Universal Clipboard angle: when **Handoff/Universal Clipboard** is on, a copy on the iPhone can transit to a nearby Mac/iPad (and vice-versa) — a cross-device leakage path worth noting in scope.

> 🔬 **Forensics note:** Because the pasteboard is "last value wins," it is volatile in the worst way — the next copy obliterates it. If clipboard content is in scope, prioritize it early in a live/AFU acquisition; a later image may have lost it. There is no clipboard *history* natively (third-party clipboard-manager apps keep their own stores in their containers — check those separately).

---

### High-value preference plists — `com.apple.*`

User and system defaults live as property lists under:

```
/private/var/mobile/Library/Preferences/        ← per-user (mobile) defaults
/private/var/preferences/                        ← lower-level system config
/private/var/root/Library/Preferences/          ← root-context defaults
```

They are managed by **`cfprefsd`** (the `NSUserDefaults`/`CFPreferences` backing daemon), so a defaults write by an app or the OS lands here as a binary plist. Most are mundane, but a handful are pattern-of-life anchors. Convert any of them with `plutil -p` / `plutil -convert xml1`.

| Plist | High-value contents |
|---|---|
| `.GlobalPreferences.plist` | `AppleLanguages` (language *order* = preferred language), `AppleLocale`, keyboard layouts — quietly reveals the user's locale/language identity |
| `com.apple.purplebuddy.plist` | Setup Assistant state — historically the **device first-setup / activation** signal (a "when was this phone first configured" anchor) |
| `com.apple.springboard.plist` | SpringBoard/home-screen state and settings (icon-layout state is also tracked by SpringBoard) |
| `com.apple.mobiletimer.plist` | Alarms, timers, world clocks — placing the user's routine and time zones of interest |
| `com.apple.preferences.datetime.plist` | Auto-set-time toggle / timezone config (relevant to timestamp-integrity arguments) |
| `com.apple.locationd.plist` / `clients.plist` | Location Services master toggle and **per-bundle** location authorization (which apps were granted location) |
| `com.apple.commcenter.plist` | Cellular/CommCenter config — carrier and SIM-related identifiers |
| `com.apple.AppStore.plist` / `com.apple.assistant.plist` / `com.apple.Maps.plist` | App Store account context, Siri config, Maps preferences/recents context |

⚠️ Bundle IDs above are stable, but **specific keys move between iOS versions** — always dump and read, don't assume a key name. Some "preferences" (known Wi-Fi networks, Bluetooth pairings) have migrated *out* of `com.apple.*` plists into dedicated stores across versions — verify on the target.

The same domain can exist in **more than one location** — `.GlobalPreferences.plist` lives both under `/var/mobile/Library/Preferences/` (the user-facing locale/language) and `/var/preferences/` (a lower-level system copy), and they can disagree. Read both; a mismatch is itself informative. Note too that `cfprefsd` buffers writes in memory and flushes lazily, so on a *live* device the on-disk plist can lag the running value — another reason to prefer a clean image or backup over scraping a running phone.

> 🖥️ **macOS contrast:** Identical mechanism to the Mac you know — `cfprefsd`, `NSUserDefaults`, `defaults read`, binary plists under `~/Library/Preferences/`. The difference is the **path prefix** (`/var/mobile/Library/Preferences/`) and the cast of `com.apple.*` domains (no Dock, no Finder; instead SpringBoard, CommCenter, purplebuddy). The reading skill is a straight transfer.

> 🔬 **Forensics note:** `.GlobalPreferences.plist` `AppleLanguages` is a subtle identity tell — a phone whose *preferred* language order is, say, Russian-then-English narrows the user population regardless of the UI language shown. And `com.apple.purplebuddy.plist` is one of the cleaner answers to "when did this device first get set up by *this* user," useful for second-hand-device and timeline-establishment questions.

---

### Misc store worth a sweep — `applicationState.db`

Two more system stores round out the "what apps, and what state" picture and are cheap to check:

- **`/private/var/mobile/Library/FrontBoard/applicationState.db`** — an SQLite store maintained by FrontBoard/SpringBoard tracking per-app **state**: bundle identifiers of installed apps, their data-container paths, and snapshot/launch bookkeeping. It is a useful **inventory of installed apps** (including ones since deleted whose rows linger) and ties a bundle ID to its on-disk container GUID — handy when you need to resolve which sandbox directory belongs to which app. Schema (`application_identifier_tab`, `kvs`, etc.) shifts across versions; dump `sqlite_master` first.
- **On-device Spotlight / CoreSpotlight index** — the on-device search index holds metadata (and sometimes content snippets) that apps donated for search, surviving the deletion of the originating item in some cases. It is a proprietary index, not plain SQLite; reach for `iLEAPP`/`mac_apt` rather than hand-querying.

Both are secondary to the stores above but belong in the sweep: `applicationState.db` answers "was app X ever installed, and where did its data live?" even after an uninstall removes the visible container.

> 🔬 **Forensics note:** `applicationState.db` is the bridge from a bundle ID (which the notification store, `Accounts3.sqlite`, and `knowledgeC` all speak) to the **container GUID** under `/private/var/mobile/Containers/Data/Application/<GUID>/`. When a recovered notification names `com.burnerchat.app` but you can't find its data, this DB tells you the GUID directory to go carve — even if the app is gone, an older image or backup may still hold that container.

---

### Putting it together — the displaced-store cheat sheet

| Store | Path (under `/private/var/mobile/Library/`) | Format | Holds content? | Survives in-app delete? | Epoch |
|---|---|---|---|---|---|
| Notification bodies | `UserNotifications/<bundle>/DeliveredNotifications.plist` | `NSKeyedArchiver` plist | **Yes** (title/body/sender) | Yes (until NC cleared) | Mac abs (2001) |
| Notification attachments | `UserNotifications/<bundle>/Attachments/` | raw media + plist | **Yes** (cached media) | Yes | — |
| Keyboard lexicon | `Keyboard/<lang>-dynamic-text.dat` | binary blob | **Yes** (typed words) | Yes (accretes) | none per-word |
| Keyboard model / dict | `Keyboard/user_model_database.sqlite`, `UserDictionary.sqlite` | SQLite | Yes | Yes | varies |
| Accounts | `Accounts/Accounts3.sqlite` | SQLite (Core Data) | identity + enable date | Yes (rows linger) | Mac abs (2001) |
| Pasteboard | `pasteboardd` (path version-specific) | typed items | **Yes** (last copy) | Yes, but last-value-only | — |
| Preferences | `Preferences/com.apple.*.plist`, `.GlobalPreferences.plist` | binary plist | config / identity | Yes | varies |
| App inventory | `FrontBoard/applicationState.db` | SQLite | bundle↔container map | rows linger post-uninstall | varies |
| On-device search | CoreSpotlight index (`CoreSpotlight/`) | proprietary index | donated metadata/snippets | sometimes outlives the item | varies |

The pattern across every row: a **system purpose** (render a banner, predict text, authenticate, share a clipboard, search) created a copy the originating app's delete path cannot reach. Sweep all of them on every exam — the cheap ones (`strings` the lexicon, `plutil` the plists) cost minutes and routinely break a case open.

---

## Hands-on

> There is **no on-device shell**. Everything below runs on your Mac against a Simulator container, a mounted/extracted file-system image, or a sample image. Copy artifacts out before parsing; deserialize on the copy.

**Locate the notification store (Simulator) and list which apps have delivered notifications:**

```bash
# Simulator system data lives under the device's data/ tree (not an app container)
SIM=~/Library/Developer/CoreSimulator/Devices/<UDID>/data
find "$SIM/Library/UserNotifications" -name 'DeliveredNotifications.plist' 2>/dev/null
# .../UserNotifications/com.apple.MobileSMS/DeliveredNotifications.plist
# .../UserNotifications/com.apple.mobilemail/DeliveredNotifications.plist
```

**Deserialize an NSKeyedArchiver notification plist (the body is *not* visible to `plutil -p`):**

```bash
# plutil shows the $objects graph, not the message — you must walk $objref:
python3 - <<'PY'
import ccl_bplist          # pip install ccl_bplist  (Alex Caithness)
with open('DeliveredNotifications.plist','rb') as f:
    plist = ccl_bplist.load(f)
    objs  = ccl_bplist.deserialise_NsKeyedArchiver(plist, parse_whole_structure=True)
    print(objs)            # title / subtitle / body / date emerge from the resolved graph
PY
```

For batch work, point `iLEAPP` at the extraction — its notifications module deserializes the whole tree and timelines it:

```bash
python3 ileapp.py -t fs -i /path/to/filesystem_extraction -o /tmp/ileapp_out
# → "Notifications" report: app, title, body, delivery time
```

**Triage the keyboard lexicon with `strings` (works on the raw binary, no parser needed):**

```bash
strings -a /path/extraction/private/var/mobile/Library/Keyboard/en_US-dynamic-text.dat | less
# Unsorted preserves rough typing order. Illustrative dump:
#   Kaitlyn
#   Hunter2024!          ← typed into a non-secure field at some point
#   2247 Birchwood
#   ledger seed
#   wagmi
#   blackbird0719
# names, slang, usernames, addresses, credential-shaped fragments — note: NO timestamps.
sqlite3 file:UserDictionary.sqlite?mode=ro 'SELECT * FROM sqlite_master;'   # the shortcut DB schema
```

**Read the Accounts database — every configured identity with its enable date:**

```bash
cp /path/extraction/private/var/mobile/Library/Accounts/Accounts3.sqlite /tmp/acc.db   # copy first
sqlite3 /tmp/acc.db "
SELECT a.ZUSERNAME,
       t.ZACCOUNTTYPEDESCRIPTION              AS service,
       a.ZIDENTIFIER                          AS guid,
       datetime(a.ZDATE + 978307200,'unixepoch','localtime') AS added
FROM ZACCOUNT a
LEFT JOIN ZACCOUNTTYPE t ON a.ZACCOUNTTYPE = t.Z_PK
ORDER BY a.ZDATE;"
# robert@gmail.com | Google   | 9F3A...  | 2024-03-11 19:02:14
# user@icloud.com  | iCloud   | 0C18...  | 2023-08-02 10:44:51
# j.doe@corp.com   | Exchange | 5B7E...  | 2024-09-30 08:15:03   ← work mail on a "personal" phone
# Order by ZDATE = the device's identity-onboarding timeline.
```

**Dump a high-value preference plist:**

```bash
plutil -p /path/extraction/private/var/mobile/Library/Preferences/.GlobalPreferences.plist | grep -A5 AppleLanguages
plutil -p /path/extraction/private/var/mobile/Library/Preferences/com.apple.purplebuddy.plist
```

**Resolve bundle IDs to container GUIDs from the app-state inventory:**

```bash
cp /path/extraction/private/var/mobile/Library/FrontBoard/applicationState.db /tmp/as.db   # copy first
sqlite3 /tmp/as.db '.tables'                       # schema varies by version — look first
sqlite3 /tmp/as.db "SELECT * FROM application_identifier_tab LIMIT 40;"
# → maps bundle identifiers to the rows the kvs/state tables key off of;
#   cross-reference to /private/var/mobile/Containers/Data/Application/<GUID>/
```

**Note on the pasteboard:** there is no portable `sqlite3` one-liner — `pasteboardd`'s persistence location is version-specific. On a live/AFU device the reliable path is a Frida hook on `UIPasteboard.general` (`-string` / `-items`) rather than carving an on-disk file; on a dead-box image, search `Caches` for `pasteboard`-named directories and treat any hit as version-dependent (confirm, don't assume).

**Locate these stores inside an iTunes/Finder backup (not just a full file system).** A logical backup hashes file paths, so you resolve them through `Manifest.db`. All three primary stores live in `HomeDomain`:

```bash
# In a decrypted backup directory (see the backup-format lesson for decryption)
sqlite3 Manifest.db "
SELECT fileID, relativePath FROM Files
WHERE domain='HomeDomain'
  AND (relativePath LIKE 'Library/UserNotifications/%'
    OR relativePath LIKE 'Library/Keyboard/%'
    OR relativePath = 'Library/Accounts/Accounts3.sqlite');"
# fileID is the SHA-1 name under the 2-hex-prefix subfolder, e.g. ab/ab12cd...
```

That `fileID` is the on-disk filename (sharded into a two-hex-char subdirectory). Copy it out, rename, and parse exactly as above. This matters because a **logical acquisition you *can* perform device-free** (an encrypted backup, then decrypt) already contains the notification store, the keyboard lexicon, and `Accounts3.sqlite` — you do not need a full-file-system extraction to reach them.

---

## 🧪 Labs

### Lab 1 — Generate and dissect a delivered notification (Substrate: Simulator)

**Fidelity caveat:** the Simulator runs macOS frameworks — it has **no SEP / Data Protection / baseband**, and device-only daemons (`knowledged`, `routined`, the Biome SEGB writers) don't populate their stores. But `simctl push` *does* exercise the real UserNotifications delivery path and writes a real `DeliveredNotifications.plist` you can dissect for **structure/format**. Lock-state survival behavior is taught from a sample image (Lab 3), not here.

1. Boot a Simulator and install a target app (or use `com.apple.MobileSMS`). Push a notification:
   ```bash
   echo '{"Simulator Target Bundle":"com.example.app",
          "aps":{"alert":{"title":"Mom","body":"call me when you land"}}}' > /tmp/n.apns
   xcrun simctl push booted com.example.app /tmp/n.apns
   ```
2. `find ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/UserNotifications -name 'DeliveredNotifications.plist'`.
3. `plutil -p` it — confirm you see a `$objects`/`$archiver` graph, **not** the body. This is the lesson: it's `NSKeyedArchiver`, not flat.
4. Deserialize with `ccl_bplist` (or run `iLEAPP`). Recover `title`/`body`/`date`. Note the date is Mac-absolute-time.
5. **Delete the app** from the Simulator, then re-check the store. Observe what the per-app directory does on uninstall — and reason about why an app-level "clear chat" (which you did *not* do) never reaches this path.

### Lab 2 — Carve the keyboard lexicon (Substrate: public sample image)

**Fidelity caveat:** the Simulator's keyboard learning does **not** populate `dynamic-text.dat` the way a real device does, so use a **public reference image** (Josh Hickman's iOS image / an iLEAPP test dataset) where the lexicon reflects real typing.

1. Locate `private/var/mobile/Library/Keyboard/` in the image. List the `*-dynamic-text.dat` files and the SQLite stores.
2. `strings -a en_US-dynamic-text.dat | less` — identify proper nouns, usernames, and any credential-looking fragments. Note that words appear *before* you sort them in roughly typed order.
3. Open `UserDictionary.sqlite` (read-only) and list the user's text-replacement shortcuts — these are *deliberate* user input, a different evidentiary weight than the learned lexicon. Then compare against `CloudUserDictionary.sqlite`: entries present in the cloud copy but not the local one imply the user typed them on **another device** signed into the same Apple Account — a cross-device inference from a single phone.
4. Write two sentences distinguishing what the lexicon can and **cannot** prove (no per-word timestamp, no app attribution → leads, not standalone proof).

### Lab 3 — Map accounts and build a first-config timeline (Substrate: public sample image)

**Fidelity caveat:** a Simulator has no real Accounts; use the sample image, where `Accounts3.sqlite` holds genuine configured identities.

1. Copy `Accounts3.sqlite` out and run the `ZACCOUNT` ⨝ `ZACCOUNTTYPE` query from Hands-on.
2. Build a chronological list of accounts by `ZDATE`. Which service was configured first? Does it line up with `com.apple.purplebuddy.plist` (device setup)?
3. Pick one account's `ZIDENTIFIER` GUID and grep the rest of the extraction for it (`grep -rl <guid>`). Which other stores reference it? (You're proving the GUID-as-join-key point.)

### Lab 4 — Cross-store corroboration (Substrate: read-only walkthrough + sample image)

1. Choose one delivered notification (Lab 1/sample) with a sender + body.
2. Find the matching **`/notification/usage`** interval in `knowledgeC.db` (`ZOBJECT`/`ZSTRUCTUREDMETADATA`) and the **`userNotificationEvents`** SEGB stream entry — both should agree on bundle + approximate time even where the *body* lives only in the plist.
3. Search the keyboard lexicon for the sender's name or a distinctive word from the body.
4. Write the corroboration paragraph: which store supplied the **content**, which supplied the **timeline**, and why four agreeing stores are harder to impeach than one recovered row.

### Lab 5 — App inventory & container resolution (Substrate: Simulator + public sample image)

**Fidelity caveat:** the Simulator maintains a real `applicationState.db`-style store under its `data/` tree so you can learn the schema, but the *deleted-app row lingering* behavior is best confirmed on a real-device sample image.

1. On a Simulator, install two apps, then dump `applicationState.db` (`.tables`, then the identifier table). Record the bundle IDs and their state rows.
2. **Delete one app.** Re-dump and observe whether the row persists. On the sample image, repeat for an app you know was uninstalled — does its bundle ID still appear?
3. Pick one surviving bundle ID and resolve it to its container GUID under `Containers/Data/Application/<GUID>/`. Confirm the directory exists (or, for the deleted app, that the row outlived the directory).
4. Tie it back: take a bundle ID that appeared in a recovered notification (Lab 1) and use `applicationState.db` to locate where that app's data *would have* lived — the exact carving target for [[deleted-data-recovery]].

---

## Pitfalls & gotchas

- **`plutil -p` on a notification plist shows you nothing useful.** `DeliveredNotifications.plist` / `AttachmentList.plist` are `NSKeyedArchiver` graphs — you must *deserialize* (`ccl_bplist`, `nska_deserialize`, `iLEAPP`, `mac_apt`), not pretty-print. Reporting "the plist had no message text" because `plutil` didn't show it is a classic miss.
- **The notification store is a moving snapshot.** It holds *currently/recently delivered* notifications; clearing Notification Center prunes it. A live acquisition is a point-in-time view — an older full-file-system image or iTunes/Finder backup may contain notifications since cleared. Don't treat "not present now" as "never delivered."
- **Wrong epoch.** Notification `date`, Accounts `ZDATE`, and most of these `NSDate`/Core Data timestamps are **Mac absolute time (2001 epoch, +978307200)**. Mixing in the Unix epoch (1970) or the WebKit/Cocoa nanosecond variants you saw elsewhere lands you ~31 years off. Confirm the unit per column.
- **The keyboard lexicon has no timestamps and no app attribution.** It proves a word was *typed at some point on this device*, not *when*, *where*, or *to whom*. Overstating a lexicon hit as a dated message is an examiner error a defense will exploit. Use it as a lead and corroborate.
- **Filenames drift.** `dynamic-text.dat` vs `<lang>-dynamic-text.dat`, `Accounts3` vs `Accounts4`, preference keys moving between versions, and Wi-Fi/Bluetooth config migrating out of `com.apple.*` plists into dedicated stores — verify exact names against the target OS version; the *mechanism* is durable, the *path* is perishable.
- **The pasteboard is last-value-only and volatile.** No native history; the next copy destroys the prior. Grab it early in a live/AFU workflow or lose it. Don't expect a clipboard timeline from the OS — only third-party clipboard managers keep one (in their own containers).
- **Copy before you query SQLite.** `Accounts3.sqlite`, `user_model_database.sqlite`, `UserDictionary.sqlite` — even a `SELECT` takes a write lock and can spawn `-wal`/`-shm` sidecars, altering the evidence. `cp` first (or open `?mode=ro` / `?immutable=1`).
- **Lock state still governs decryptability.** These are Data-Protection-class files. On a **BFU** device most are encrypted and unreadable until first unlock; the survival properties above only help once you have a decrypted file-system image or an AFU acquisition. See [[app-sandbox-and-filesystem-layout]] and the BFU/AFU lesson.
- **The lexicon is a privacy minefield in reporting, not just analysis.** A `strings` dump can surface third parties' names, the suspect's passwords, medical terms, and unrelated people's data with no context. Scope your extraction and your report — pulling the *whole* lexicon into a disclosed exhibit can over-collect well beyond the warrant. Carve for the terms in scope; don't dump the user's entire typed history into the record by reflex.
- **`NSKeyedArchiver` versions and custom classes.** Notification payloads occasionally embed app-custom classes the deserializer doesn't know; a naïve walk can throw or silently drop a branch. Prefer a maintained parser (`iLEAPP`/`mac_apt`) and spot-check its output against a manual `ccl_bplist` walk on at least one record before trusting a bulk run.

## Key takeaways

- **The notification store holds message bodies the app no longer does.** `/private/var/mobile/Library/UserNotifications/<bundle>/DeliveredNotifications.plist` (an `NSKeyedArchiver` plist) preserves sender + preview text — including for deleted or disappearing messages — written by the OS, untouched by app-level deletion.
- **The keyboard lexicon is a passive partial keylog with no Mac equivalent.** `<lang>-dynamic-text.dat` accretes the unique words the user typed across all apps; `strings` triages it instantly, and it routinely survives wipes — but it carries no timestamp or app attribution, so it yields *leads*.
- **`Accounts3.sqlite` catalogues every configured identity and when it was enabled.** `ZACCOUNT` ⨝ `ZACCOUNTTYPE` gives service, username, GUID, and a Mac-absolute-time enable date; the GUID is a join key into `interactionC` and other stores.
- **The pasteboard yields the last copied secret** (`pasteboardd`, `com.apple.UIKit.pboard.general`) — persistent across reboot/uninstall but last-value-only and volatile; grab it early.
- **A few dozen `com.apple.*` preference plists are pattern-of-life anchors** — `.GlobalPreferences` (language/locale identity), `com.apple.purplebuddy` (first setup), `locationd` per-app authorization, `commcenter` (carrier/SIM) — read via `cfprefsd`/`plutil`, same skill as macOS `defaults`.
- **The displacement principle is the meta-lesson:** evidence the user thought they deleted survives because the OS copied it sideways for a system purpose into a different sandbox owner with lazy GC. Hunt the spill, then corroborate across stores.
- **Mechanism is durable; paths and filenames are perishable** — verify exact names/keys/epochs against the target iOS version every time.

## Terms introduced

| Term | Definition |
|---|---|
| Displacement principle | The observation that user content survives deletion because iOS copies it into a system-owned store (notifications, lexicon, accounts, pasteboard) decoupled from the originating app |
| `DeliveredNotifications.plist` | Per-app `NSKeyedArchiver` plist under `UserNotifications/` holding delivered-notification title/body/sender/timestamps; survives in-app message deletion |
| `NSKeyedArchiver` plist | A serialized object-graph plist (`$objects`/`$top`/`$objref`) that must be deserialized, not pretty-printed, to read its payload |
| `UserNotificationsServer` / BulletinBoard | The system notification pipeline (UserNotifications framework + SpringBoard's BulletinBoard layer) that writes the delivered-notification store; push transport via `apsd`. Exact internal process names are version-specific |
| `userNotificationEvents` | DuetExpertCenter/Biome SEGB stream logging notification delivery/dismissal events (timeline, usually no body) |
| `dynamic-text.dat` / `<lang>-dynamic-text.dat` | Proprietary binary keyboard learned-lexicon files that accrete unique typed words per keyboard language; a partial keylog |
| `user_model_database.sqlite` | Newer SQLite keyboard learning/typing-model store under `Library/Keyboard/` |
| `UserDictionary.sqlite` / `CloudUserDictionary.sqlite` | User-defined text-replacement shortcuts (local / iCloud-synced) |
| `Accounts3.sqlite` | iOS Accounts-framework database (`ZACCOUNT`/`ZACCOUNTTYPE`) listing every configured account, identifiers, and enable dates (`Accounts4` on desktop) |
| `ZACCOUNT` / `ZACCOUNTTYPE` | Core Data tables for individual accounts and their service type; `ZIDENTIFIER` GUIDs act as join keys into other stores |
| `pasteboardd` | Daemon brokering the system clipboard; the general pasteboard (`com.apple.UIKit.pboard.general`) persists the last copied value across reboot/uninstall |
| `cfprefsd` | Daemon backing `NSUserDefaults`/`CFPreferences`; writes the `com.apple.*` preference plists |
| `com.apple.purplebuddy.plist` | Setup Assistant preferences plist; a "device first set-up by this user" anchor |
| `applicationState.db` | FrontBoard/SpringBoard SQLite inventory of installed apps mapping bundle IDs to data-container GUIDs; rows can linger after uninstall |
| `ccl_bplist` | Alex Caithness's Python library for parsing binary plists and deserializing `NSKeyedArchiver` object graphs |
| Mac absolute time | Timestamp epoch 2001-01-01 UTC used by `NSDate`/Core Data here; add 978307200 for Unix epoch |

## Further reading

- Apple — *UserNotifications* framework and *UIPasteboard* documentation (developer.apple.com); *Accounts* (`ACAccount`/`ACAccountStore`) reference
- Heather Mahalik & co. — SANS **FOR585** (Smartphone Forensics) iOS artifact coverage of notifications, keyboard, and accounts
- d204n6 (Geraldine Blay) — "iOS 12: Delivered Notifications and a new way to parse them" (blog.d204n6.com)
- The Forensic Scooter — "iOS KnowledgeC.db Notifications" (`/notification/usage`) and DFIR Review's "Peeking at User Notification Events in iOS 15"
- Forensafe — "iOS User Notification Events" and "Apple Accounts" (forensafe.com/blogs)
- Athena Forensics / Tetra Defense — the user-dictionary / `dynamic-text.dat` "favorite artifact" write-ups; Mattia Epifani (RealityNet) **iOS-Forensics-References** (curated artifact path index)
- Alexis Brignoni — **iLEAPP** (notifications, keyboard, accounts modules); Yogesh Khatri — **mac_apt** iOS plugins
- Alex Caithness (CCL Solutions) — `ccl_bplist` / `NSKeyedArchiver` deserialization; `ccl-segb` for the SEGB notification stream
- Mysk — "Popular iPhone and iPad Apps Snooping on the Pasteboard" (pasteboard-privacy background)
- `man strings`, `man plutil`, `man sqlite3`, `xcrun simctl help push`

---
*Related lessons: [[app-sandbox-and-filesystem-layout]] | [[knowledgec-db-deep-dive]] | [[biome-and-segb-streams]] | [[communications-imessage-and-sms]] | [[the-ios-timestamp-zoo]] | [[deleted-data-recovery]]*
