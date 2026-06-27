---
title: "Safari & third-party browsers"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 08
est_time: "45 min read + 20 min labs"
prerequisites: [app-sandbox-and-filesystem-layout]
tags: [ios, forensics, safari, browser, history, cookies, dfir]
last_reviewed: 2026-06-26
---

# Safari & third-party browsers

> **In one sentence:** Safari scatters a suspect's web life across a half-dozen SQLite databases and one proprietary binary blob in `/private/var/mobile/Library/Safari/` and `.../Cookies/` — history, currently-open tabs, recently-closed tabs that survive a "Clear History," cross-device tabs that betray the whole iCloud device fleet, and authenticated-session cookies — while Chrome and Firefox keep parallel, broadly cross-platform stores inside their own app containers, and the whole picture only reconstructs correctly if you keep the WebKit (1601) and Mac-Absolute (2001) epochs straight.

## Why this matters

Browsing is the densest single source of intent in a phone exam. Where the user *went*, what they *searched*, what tabs they had *open at seizure*, and — through iCloud tab sync — what *other devices they own* are all sitting in plain SQLite once you have a file-system image. Unlike Messages or Photos, browser artifacts also tell you about activity that left no other on-device trace: a single GET to a darkweb market, a Google search string in a URL, a logged-in session cookie that proves account control. The catch is that this is a multi-store, multi-epoch problem. Safari spreads state across History, tab, bookmark, and cookie stores that update and prune on different schedules; "Clear History" empties some of them and leaves others untouched; and the timestamp inside each store is one of *at least two* epochs, so a careless `datetime()` conversion silently puts an event 400 years off (the 1601↔2001 epoch gap). This lesson is the practitioner map: every store, its on-disk format, the table and column names, the correct epoch, what "private browsing" and "clear history" actually do to each, and how third-party browsers parallel it.

## Concepts

### The Safari artifact set — one directory, six stores

Safari is a first-party system app, so its data does **not** live in a randomized `Containers/Data/Application/<GUID>/` sandbox like a third-party app. It sits at a fixed, well-known path on the Data volume:

```
/private/var/mobile/Library/Safari/
├── History.db                  SQLite  — visited URLs + per-visit rows
├── History.db-wal / -shm       WAL sidecars (commit these too — see Pitfalls)
├── BrowserState.db             SQLite  — tab/session state (legacy + closed tabs)
├── SafariTabs.db               SQLite  — currently-open tabs (iOS 16+)
├── CloudTabs.db                SQLite  — tabs open on the user's OTHER iCloud devices
├── Bookmarks.db                SQLite  — bookmarks + Reading List
├── RecentlyClosedTabs.plist    binary plist — recently-closed tabs (SURVIVES history clear)
└── Downloads.plist             binary plist — download manager queue/history

/private/var/mobile/Library/Cookies/
└── Cookies.binarycookies       proprietary binary — Safari/system cookie jar

/private/var/mobile/Library/Caches/com.apple.mobilesafari/
└── Cache.db                    SQLite  — legacy WebKit URL cache (see "The cache" below)
```

> 🖥️ **macOS contrast:** This is the *same software* you dissected in macOS-mastery, just relocated. On the Mac the set lives in `~/Library/Safari/` (`History.db`, `Bookmarks.db`, `CloudTabs.db`) and `~/Library/Cookies/Cookies.binarycookies`, with the identical schemas and the identical Mac-Absolute-Time-vs-WebKit-epoch trap. If you can parse macOS Safari, you can parse iOS Safari — the only differences are the path prefix (`/private/var/mobile/` instead of `~`), the addition of `SafariTabs.db` on the tab side, and that everything here is encrypted at rest until first unlock (AFU) under Data Protection. See [[03-the-itunes-finder-backup-format]] for what survives into a backup vs. a full file-system image.

> 🔬 **Forensics note:** Safari being a *fixed-path* system app is a gift. With a third-party browser you must first resolve which random `Containers/Data/Application/<GUID>/` directory belongs to it (via the `.com.apple.mobile_container_manager.metadata.plist` → `MCMMetadataIdentifier` bundle-ID map). Safari needs no such hunt — but the trade-off is that Safari data is class **`NSFileProtectionCompleteUntilFirstUserAuthentication`**, so on a BFU (Before First Unlock) device the files are present but undecryptable until the passcode is entered once. See [[02-bfu-vs-afu-and-data-protection-classes]].

### History.db — `history_items` ⋈ `history_visits`

`History.db` is the spine. Two tables matter, joined one-to-many:

| Table | Key columns | Meaning |
|---|---|---|
| `history_items` | `id`, `url`, `domain_expansion`, `visit_count`, `daily_visit_counts` | One row per **distinct URL** ever visited |
| `history_visits` | `id`, `history_item` (→ `history_items.id`), `visit_time`, `title`, `load_successful`, `origin`, `redirect_source`, `redirect_destination`, `http_non_get` | One row per **individual visit** to a URL |

The relationship is the whole game: `history_items` deduplicates URLs and carries a running `visit_count`; `history_visits` is the time series — each row a discrete navigation event with its own `visit_time`. Join them on `history_visits.history_item = history_items.id`.

**The epoch — this is the trap.** `history_visits.visit_time` is **Mac Absolute Time** (a.k.a. `CFAbsoluteTime`): a floating-point count of seconds since `2001-01-01 00:00:00 UTC`. To get a wall-clock time, add `978307200` (the seconds between the Unix and Apple epochs) and treat it as Unix time:

```sql
datetime(visit_time + 978307200, 'unixepoch', 'localtime')
```

`redirect_source` / `redirect_destination` chain visits together: a search-engine result page that bounced you onward leaves a `redirect_source` pointing back at the SERP visit. `origin` distinguishes a typed/clicked navigation from a synced one. `load_successful = 0` means the navigation was attempted but failed — still evidence of *intent to visit*.

> 🔬 **Forensics note:** Search terms are usually right there in `history_items.url` as query parameters (`google.com/search?q=...`, `duckduckgo.com/?q=...`). You rarely need a separate "search history" artifact for the big engines — URL-decode the `q=` parameter. Combine that with `history_visits.visit_time` and you have *what they searched, exactly when*. Private-mode visits are the exception: they are **never written to `History.db`** (see below).

### Private Browsing — what it does and doesn't leave

Safari Private Browsing tabs are **not** recorded in `History.db`, and their cookies are kept in an ephemeral in-memory jar that is discarded on tab close — so the textbook answer is "private mode leaves nothing on disk." In practice, that is *mostly* true but not absolute:

- **Open private tabs persist across reboot.** Since iOS 15, Private tabs that are still open survive a relaunch, which means their session state can land in the tab stores (`SafariTabs.db` / `BrowserState.db`) — flagged as private — until the tab is actually closed.
- **DNS/QUIC and OS-level caches** outside Safari (e.g., the `routined`/network stacks, `Cache.db`, favicon DB) can still hold corroborating fragments.
- **`RecentlyClosedTabs.plist`** does *not* capture private tabs.

So "private mode" defeats `History.db` but the *open private tab* itself is acquirable from a live/AFU device.

> 🔬 **Forensics note:** A user who browsed something in Private mode and left the tab open at seizure is recoverable; a user who closed it is mostly not (from Safari's own stores). This makes lock-state and "were tabs open at seizure" a deciding factor — another reason an AFU acquisition is worth orders of magnitude more than BFU.

### The tab stores — `SafariTabs.db`, `BrowserState.db`, and the BLOB plists

Tab state moved around across iOS versions, which is exactly why you check *all* of them:

- **`SafariTabs.db`** — since **iOS 16**, the store of **currently-open tabs**. Counterintuitively, the tab rows live in a table called **`bookmarks`** (Safari reuses the bookmark schema for the tab tree); per-tab payload sits in BLOB columns.
- **`BrowserState.db`** — the **legacy** tab store. On modern iOS it retains the most-recently-open tab at suspend and, importantly, **closed-tab session history** (`tabs` table with a private-mode flag; `tab_sessions` table with prior session detail). On an upgraded device it can still hold tabs migrated from iOS 15.

The forensic value is buried in two BLOB columns common to these stores — both are **binary plists**:

| BLOB column | Contents |
|---|---|
| `extra_attributes` | Per-tab flags — was the link opened, muted, etc. — plus a nested `SessionState` value |
| `local_attributes` | The richest: the tab itself **and all its session data** (full back/forward navigation list for that tab) |

Two gotchas when you crack these BLOBs:

1. **They are nested plists** — a binary plist whose values include *another* serialized plist (the `SessionState`). You decode, find the inner blob, decode again.
2. **Apple pads the `SessionState` bytes** — the first 4 bytes are padding that sit *before* the `bplist00` magic actually begins (per d204n6's iOS 16 teardown). Strip to the magic before handing it to a plist parser, or the parse fails. (This same padding quirk exists in `BrowserState.db` and `SafariTabs.db` — it's a known Safari serialization habit, not corruption.)

The `SessionState` back/forward list is gold: it preserves the **navigation history *within a single tab*** — pages the user moved through in that tab — which is *not* the same as `History.db` and can include entries pruned from history.

```
SafariTabs.db / BrowserState.db
        │
   bookmarks / tabs  ──┐
        │              │  local_attributes (BLOB)
        │              └─► bplist00 ──► SessionState (padded bplist00)
        │                                   └─► [back/forward URL list, scroll, title]
        │
   extra_attributes (BLOB) ──► bplist00 ──► flags + SessionState ref
```

### `RecentlyClosedTabs.plist` — the store that outlives "Clear History"

`RecentlyClosedTabs.plist` is a binary plist of tabs the user closed but Safari can still re-open from the tab UI. Its forensic significance is disproportionate to its size: **it is not wiped by "Clear History and Website Data."** A suspect who closes a tab and then clears history believes the URL is gone; `History.db` is indeed cleared, but the closed tab's URL and title can persist in this plist. Always parse it independently of `History.db`, and treat any URL present here but *absent* from a cleared `History.db` as a strong indicator of a history clear.

### `CloudTabs.db` — the device-fleet link

`CloudTabs.db` records **iCloud Tabs**: the tabs open in Safari on the user's *other* signed-in Apple-account devices (their Mac, iPad, another iPhone). It carries a per-device table (commonly `cloud_tab_devices`) listing each device by name/UUID and a tabs table mapping open URLs to the device they're open on.

This is the single most under-appreciated browser artifact for *attribution and scoping*. From one seized iPhone you can enumerate the **entire Apple-account device fleet** by name and infer URLs open elsewhere — which can justify a warrant for a second device, prove a suspect controls a particular Mac, or corroborate cross-device coordination. It only populates when the account is signed in and "Safari" is enabled in iCloud sync.

> ⚖️ **Authorization:** `CloudTabs.db` exposes devices and URLs that belong to systems *outside* the one you seized. Enumerating the fleet is fair game on the device you lawfully hold; *acquiring those other devices* is a separate authorization. Document the fleet discovery in your notes — it's both a lead and a scope boundary. See [[00-ios-forensics-landscape-and-authorization]].

### `Bookmarks.db` — bookmarks + Reading List

`Bookmarks.db` holds the bookmark tree and, in the same database, the **Reading List**. Reading List rows carry an `extra_attributes` BLOB (again a binary plist) with the date added, a server-fetched preview/excerpt of the page, and fetch timestamps — i.e., a *saved snapshot of content* the user explicitly chose to keep, with its own timeline. Bookmarks express durable intent; a bookmark to a specific resource is a deliberate act in a way a transient history hit is not.

### `Cookies.binarycookies` — authenticated-session evidence in a proprietary format

Cookies are **not** SQLite. Safari/system cookies live at `/private/var/mobile/Library/Cookies/Cookies.binarycookies` in Apple's proprietary `binarycookies` format. You cannot `sqlite3` it; you need a dedicated parser (`BinaryCookieReader.py`, mac_apt's cookie plugin, or any commercial suite).

Format sketch (enough to know why it needs a special reader):

```
Offset  Field
0x00    "cook"  signature (4 bytes)
0x04    num_pages (4 bytes, BIG-endian)        ◄── endianness flips mid-file
0x08    page_size[ ] (4 bytes each, big-endian)
...     pages, each containing cookie records:
          per-record: url, name, path, value (NUL-terminated strings)
          flags (secure / HTTP-only), and TWO dates:
          creation_time + expiration_time
          stored as 8-byte LITTLE-endian doubles = Mac Absolute Time (2001 epoch)
```

The endianness switch (big-endian header/page counts, little-endian doubles inside records) and the size-map layout are why naive parsing fails. The two dates are **Mac Absolute Time** doubles — add `978307200` exactly as for `History.db`.

Forensically, cookies are **proof of authenticated sessions**. A live session cookie for a webmail, bank, or social account is direct evidence the user was *logged in* to that account on that device — far stronger than a history hit, which only proves a page loaded. Cookie `creation_time` timelines the first login; domains present prove account *relationships* even when history is cleared (cookies are *not* always cleared with history depending on how the user cleared it).

> 🖥️ **macOS contrast:** Byte-for-byte the same `Cookies.binarycookies` format you parsed at `~/Library/Cookies/` on macOS, same `cook` magic, same mixed endianness, same 2001-epoch doubles. The reader you already have works unchanged on the iOS copy.

### The cache — `Cache.db` and the WebKit network cache

The legacy SQLite URL cache lives at `/private/var/mobile/Library/Caches/com.apple.mobilesafari/Cache.db` and stores cached request URLs, server responses, and timestamps — recoverable rendered content for pages the user actually loaded. Modern WebKit also keeps a separate **blob-based NetworkCache** (a hashed on-disk store under the WebKit caches hierarchy) and WebKit local storage at `/private/var/mobile/Library/WebKit/`.

> ⚠️ The exact 2026 path/layout of the modern WebKit blob NetworkCache (and whether `Cache.db` is still populated on iOS 26 vs. fully superseded) is version-volatile — **verify against your sample image rather than trusting a hard-coded path.** The durable point: cached *response bodies* are recoverable separately from history, so a page can be reconstructed even if its `History.db` row was cleared.

### Third-party browsers — parallel stores, different epoch

Chrome, Firefox, Edge, Brave, DuckDuckGo, etc. are sandboxed apps. Each keeps its **own** datastore inside its private container:

```
/private/var/mobile/Containers/Data/Application/<random-GUID>/
```

You first resolve the GUID → app mapping via each container's hidden metadata plist:

```
<GUID>/.com.apple.mobile_container_manager.metadata.plist
        └─ MCMMetadataIdentifier = com.google.chrome.ios   (the bundle ID)
```

Once located, the schemas are **broadly cross-platform** — the same files you parse on desktop Chrome/Firefox:

| Browser | Store (relative to container) | Format | History tables | Time epoch |
|---|---|---|---|---|
| Chrome (iOS) | `Library/Application Support/Google/Chrome/Default/History` | SQLite | `urls`, `visits` | **WebKit/Chrome epoch** — µs since **1601** |
| Chrome (iOS) | `.../Default/Cookies`, `.../Default/Login Data` | SQLite | — | — |
| Chrome (iOS) | `.../Default/Bookmarks` | JSON | — | — |
| Firefox (iOS) | profile dir (`...default*/`), `places`-style DB | SQLite | `moz_places`, `moz_historyvisits` | µs since **Unix** epoch (1970) |

> ⚠️ The exact Firefox-iOS profile path and history DB filename (it has migrated between `browser.db` and a Rust `places.db` application-services store) is version-volatile — **locate it with `find` and inspect the table names rather than assuming a filename.**

### In-app browsers — `WKWebView` and `SFSafariViewController`

A huge fraction of "browsing" on iOS never happens in a browser at all. Tapping a link inside Instagram, a messaging app, a news reader, or an email client opens either an **`SFSafariViewController`** (a full Safari instance hosted by the app) or a **`WKWebView`** (the app's own embedded web engine). The two leave very different traces:

- **`SFSafariViewController`** shares cookies and (on some configurations) state with Safari proper, but its history is **isolated** — it does *not* write to `History.db`. So a URL a suspect opened from inside a chat app may be invisible in Safari's history yet still reachable through the **hosting app's** artifacts (the message/link that launched it) and through any cookies the session set.
- **`WKWebView`** is fully containerized inside the *host app*. Its cache, cookies (a `WebKit/WebsiteData` store), local storage, and IndexedDB land under that app's `Containers/Data/Application/<GUID>/Library/` — **not** under Safari and **not** in `Cookies.binarycookies`. Each app that embeds a web view is therefore its *own* mini browser-forensics problem.

```
<app-GUID>/Library/
├── Cookies/Cookies.binarycookies          ← that app's WKWebView cookie jar
├── Caches/<...>                            ← WKWebView URL/response cache
└── WebKit/WebsiteData/                     ← local storage, IndexedDB, service-worker data
```

> 🔬 **Forensics note:** When `History.db` is thin but the user clearly browsed, look *inside the apps*. The link came from somewhere — a Messages bubble, an email, a social feed — and the rendered page or its cookies may sit in that app's container even though Safari knows nothing about it. This is the bridge to [[11-third-party-app-methodology]]: treat every app that can open a link as a potential browser.

### Auxiliary stores — favicons, Safe Browsing, downloads

Three smaller Safari-adjacent artifacts round out the picture:

| Artifact | Path (typical) | Value |
|---|---|---|
| `Favicons.db` | `.../Library/Image Cache/Favicons/Favicons.db` (+ `Favicon Cache/`) | SQLite mapping page URLs → site icons; can corroborate a visited domain even when a history row is gone, and timestamps the *first* favicon fetch |
| Safe Browsing cache | `.../Library/Caches/com.apple.Safari.SafeBrowsing/Cache.db` | Google/Apple Safe Browsing lookups — evidence Safari *checked* a URL, useful to confirm a navigation attempt |
| `Downloads.plist` | `/private/var/mobile/Library/Safari/Downloads.plist` | Binary plist of the Safari download manager: source URL, local path, byte counts, state — proves a file was fetched and where it landed |

`Downloads.plist` deserves special attention: it links a **remote URL to a local file path**, so it ties a downloaded artifact (which you may find elsewhere in the file system) back to its provenance and the moment it was fetched — exactly the chain-of-custody link a "where did this file come from?" question needs.

**The epoch mixing trap.** Chrome on iOS stores `urls.last_visit_time` and `visits.visit_time` in the **WebKit/Chrome epoch**: microseconds since `1601-01-01 00:00:00 UTC`. To convert:

```sql
datetime(last_visit_time/1000000 - 11644473600, 'unixepoch', 'localtime')
```

So in the *same forensic case*, on the *same phone*, Safari's `History.db` is **Mac Absolute Time (2001, seconds)** and Chrome's `History` is **WebKit/Chrome epoch (1601, microseconds)**. Apply the wrong conversion and the timestamp can land wildly off — cross the 1601 and 2001 epoch *bases* and you're ~400 years out; read microseconds as seconds and you're off by a factor of a million (eons into the future). Those gross errors are usually obvious. The dangerous one is subtle: forget the `978307200` add on a Safari row and the date lands exactly **31 years early** (the 1970↔2001 gap) — a *plausible-looking but wrong* date that sails through review. Build the conversion into the query per store; never eyeball it.

> 🔬 **Forensics note:** "WebKit" is a *misnomer trap* here. Safari is literally built on WebKit yet uses Mac Absolute Time in its SQLite; Chrome descends from WebKit/Blink yet uses the "WebKit epoch" (1601). The name tells you nothing about which epoch a given store uses. Tie the epoch to the *file you're reading* (Safari `History.db` → 2001; Chromium `History` → 1601; Firefox → 1970), not to the word "WebKit." See [[00-the-ios-timestamp-zoo]].

## Hands-on

All commands run on the **Mac** — there is no on-device shell. They assume you have either a mounted/extracted file-system image, a Simulator data tree, or copied artifact files. **Copy before you query**: even a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`.

### Locate and copy the Safari set from an extracted image

```bash
# From an extracted full-file-system image root ($IMG):
IMG=/path/to/extraction/filesystem
ls -la "$IMG/private/var/mobile/Library/Safari/"
# History.db  BrowserState.db  SafariTabs.db  CloudTabs.db  Bookmarks.db
# RecentlyClosedTabs.plist  Downloads.plist  History.db-wal  History.db-shm

# Copy the WHOLE store incl. WAL/SHM sidecars (a bare cp of History.db loses
# uncheckpointed rows still in the -wal):
mkdir -p ~/case/safari
cp "$IMG"/private/var/mobile/Library/Safari/History.db* ~/case/safari/
cp "$IMG"/private/var/mobile/Library/Cookies/Cookies.binarycookies ~/case/safari/
```

### History timeline (Mac Absolute Time → local)

```bash
sqlite3 ~/case/safari/History.db "
SELECT
  datetime(v.visit_time + 978307200, 'unixepoch', 'localtime') AS visited,
  i.url,
  v.title,
  i.visit_count,
  v.load_successful
FROM history_visits v
JOIN history_items i ON v.history_item = i.id
ORDER BY v.visit_time DESC
LIMIT 50;"
```

Expected: a reverse-chronological list of visits with human-readable times. Rows with `load_successful = 0` are attempted-but-failed loads. Watch for `?q=` query strings — those are searches.

### Pull search terms out of the URLs

```bash
sqlite3 ~/case/safari/History.db "
SELECT datetime(v.visit_time + 978307200,'unixepoch','localtime') AS t, i.url
FROM history_visits v JOIN history_items i ON v.history_item=i.id
WHERE i.url LIKE '%q=%' OR i.url LIKE '%search%'
ORDER BY v.visit_time DESC LIMIT 40;"
```

### Cookies — authenticated-session evidence

```bash
# binarycookies is NOT sqlite — use a parser:
python3 BinaryCookieReader.py ~/case/safari/Cookies.binarycookies
# Cookie : SID=...   Host : .google.com   Path : /
#   Created : 2026-05-12 09:14:03   Expires : 2027-05-12 09:14:03   Secure HTTPOnly
# A live (un-expired) session cookie for a webmail/bank/social host = the user
# was LOGGED IN to that account on this device.
```

### Crack a tab BLOB (nested, padded plist)

```bash
# SafariTabs.db tab rows live in the `bookmarks` table; local_attributes is a BLOB.
sqlite3 ~/case/safari/SafariTabs.db ".schema bookmarks"
# Dump one local_attributes BLOB to a file, then strip leading pad to bplist00:
sqlite3 ~/case/safari/SafariTabs.db \
  "SELECT writefile('/tmp/tab0.bin', local_attributes) FROM bookmarks LIMIT 1;"
# find the bplist00 magic offset, carve from there, then:
plutil -p /tmp/tab0_carved.plist     # inspect the SessionState back/forward list
```

### Enumerate the iCloud device fleet from CloudTabs.db

```bash
sqlite3 ~/case/safari/CloudTabs.db ".tables"
# cloud_tabs  cloud_tab_devices  ...
sqlite3 ~/case/safari/CloudTabs.db \
  "SELECT device_name, device_uuid FROM cloud_tab_devices;"   # column names vary by version — confirm with .schema
# Each row is ANOTHER device on the suspect's Apple account.
```

### Locate a third-party browser's store

```bash
# Resolve which container GUID is Chrome:
for d in "$IMG"/private/var/mobile/Containers/Data/Application/*/; do
  id=$(plutil -extract MCMMetadataIdentifier raw \
        "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null)
  case "$id" in com.google.chrome.ios|org.mozilla.ios.Firefox) echo "$id  $d";; esac
done

# Chrome history uses the WebKit/Chrome (1601) epoch — note the DIFFERENT conversion:
CH="$IMG/private/var/mobile/Containers/Data/Application/<GUID>/Library/Application Support/Google/Chrome/Default/History"
cp "$CH" ~/case/chrome_History
sqlite3 ~/case/chrome_History "
SELECT datetime(last_visit_time/1000000 - 11644473600,'unixepoch','localtime') AS visited,
       url, title, visit_count
FROM urls ORDER BY last_visit_time DESC LIMIT 30;"
```

### Batch with the community tooling

```bash
# iLEAPP parses the whole Safari set (history, tabs, recently-closed, cloud tabs)
# plus third-party browsers from an extraction folder or tar:
python3 ileapp.py -t fs -i /path/to/extraction -o ~/case/ileapp_out
# mac_apt's SAFARI plugin works against macOS *and* iOS images.
```

## 🧪 Labs

> **Substrate note:** The Simulator runs Safari (MobileSafari) and *does* create a real `History.db`, `Cookies.binarycookies`, and tab stores on the Mac, unencrypted — perfect for learning **schema and parsing**. ⚠️ Fidelity caveat: the Simulator has **no Data-Protection-at-rest**, so you skip the BFU/AFU decryption step entirely; and `CloudTabs.db` will be **empty/absent unless you sign the Simulator into a real Apple Account with Safari sync** — the device-fleet artifact is an iCloud-populated, device-only behavior. Use a **public sample image** (Josh Hickman's iOS reference images) for a realistic, multi-device `CloudTabs.db` and for cleared-history scenarios.

### Lab 1 — Build Safari `History.db` in the Simulator and parse it (Simulator)

1. Boot a Simulator and find its data root:
   ```bash
   xcrun simctl list devices booted        # get the UDID
   DEV=~/Library/Developer/CoreSimulator/Devices/<UDID>/data
   ```
2. In the Simulator's Safari, visit several sites and run a couple of web searches.
3. Locate the history DB (don't hard-code the path — discover it):
   ```bash
   find "$DEV" -name History.db 2>/dev/null | grep -i safari
   ```
4. `cp` the DB **plus its `-wal`/`-shm`** to a working dir, then run the History timeline query from Hands-on. Confirm your visited URLs and the search `?q=` strings appear, with correct local times. **Deliverable:** the SQL you used and three rows proving the 2001-epoch conversion is right (cross-check one against the clock when you visited it).

### Lab 2 — Prove "Clear History" leaves `RecentlyClosedTabs.plist` behind (Simulator)

1. Open 3–4 tabs in Simulator Safari, then **close** one or two (so they enter recently-closed).
2. Locate and parse the plist:
   ```bash
   find "$DEV" -name RecentlyClosedTabs.plist 2>/dev/null
   plutil -p "<that path>"
   ```
3. Now use Safari → Clear History. Re-query `History.db` (expect it emptied of those visits) and re-`plutil -p` the `RecentlyClosedTabs.plist`.
4. **Deliverable:** show that the closed-tab URLs persist in the plist *after* `History.db` was cleared — the anti-forensic gap a suspect overlooks. Note in your write-up that private-mode tabs would *not* appear here.

### Lab 3 — Crack a tab-state BLOB (Simulator)

1. With several tabs open, locate `SafariTabs.db` (`find "$DEV" -name SafariTabs.db`).
2. `.schema bookmarks` to see the BLOB columns; `writefile` one `local_attributes` BLOB to disk.
3. Find the `bplist00` magic (`xxd | grep -m1 bplist00` to get the offset), carve from there, and `plutil -p` it. Then dig into the nested, padded `SessionState`.
4. **Deliverable:** extract the **back/forward navigation list** for one tab from `SessionState` and explain how it differs from `History.db` (per-tab navigation vs. global dedup'd history). Note the leading-pad-before-`bplist00` quirk you had to strip.

### Lab 4 — Parse `Cookies.binarycookies` and read session evidence (Simulator)

1. Log into a throwaway web account in Simulator Safari.
2. `find "$DEV" -name Cookies.binarycookies`, copy it out, run `BinaryCookieReader.py` against it.
3. **Deliverable:** identify the session cookie for the host you logged into, report its `Created`/`Expires` (confirm they're 2001-epoch doubles converting sanely), and the `Secure`/`HTTPOnly` flags. Explain *why a live cookie is stronger evidence of account control than a history hit*.

### Lab 5 — The epoch trap, side by side (public sample image, or Simulator + sample)

1. From a sample image (or a Simulator with Chrome installed and browsed), pull **Safari `History.db`** and **Chrome `History`**.
2. Run the *Safari* query with `+ 978307200` and the *Chrome* query with `/1000000 - 11644473600`.
3. Now deliberately swap the conversions (apply the Safari math to Chrome's `last_visit_time` and vice-versa).
4. **Deliverable:** record the wrong dates each swap produces (applying Safari's `+ 978307200` to a Chrome µs-since-1601 value lands you absurdly far in the future; applying Chrome's `/1e6 - 11644473600` to a Safari seconds-since-2001 value collapses back to ~1601) and write a one-line rule that ties the epoch to the file, not the word "WebKit." This is the [[00-the-ios-timestamp-zoo]] lesson in miniature.

### Lab 6 — Enumerate a device fleet from `CloudTabs.db` (public sample image)

1. On a multi-device Hickman-style sample image, copy `CloudTabs.db`.
2. `.schema` it, then enumerate `cloud_tab_devices` (confirm the actual column names — they drift by version).
3. **Deliverable:** list every *other* device on the suspect's Apple account and the URLs open on them. Write the one sentence you'd put in a report justifying a follow-on warrant for one of those devices — and the ⚖️ note on why you can *enumerate* them but not *acquire* them from this seizure.

## Pitfalls & gotchas

- **The epoch trap is the #1 silent error.** Safari (`History.db`, `Cookies.binarycookies`) = **Mac Absolute Time, seconds since 2001** (`+ 978307200`). Chromium browsers = **WebKit/Chrome epoch, microseconds since 1601** (`/1e6 - 11644473600`). Firefox = **microseconds since 1970**. Wrong conversion → plausible-but-wrong dates. Bind the math to the file.
- **"WebKit" ≠ "WebKit epoch."** Safari is built on WebKit but does *not* use the 1601 "WebKit epoch." Don't infer the epoch from the engine name.
- **Copy the WAL/SHM sidecars, not just the `.db`.** SQLite in WAL mode keeps uncommitted (and recently committed) rows in `History.db-wal`. A bare `cp History.db` can silently lose the most recent visits. Copy `History.db*`. And never open the live/original DB — it write-locks even on `SELECT`.
- **"Clear History" is selective.** It empties `History.db` (and some tab state) but **`RecentlyClosedTabs.plist`** can survive, and **cookies/cache** may persist depending on how the user cleared. Treat a near-empty `History.db` next to a populated `RecentlyClosedTabs.plist`/cookie jar as a *history-clear indicator*, not proof of no activity.
- **Private mode leaves no `History.db` rows** — but an *open* private tab can sit in the tab stores (flagged private) until closed. Lock state at seizure decides whether you get it.
- **Tab BLOBs are nested and padded.** `local_attributes`/`extra_attributes` are binary plists containing a *further* binary plist (`SessionState`) that has leading pad bytes before `bplist00`. Strip to the magic or the parse fails — that's a known Safari quirk, not corruption.
- **Third-party browsers hide behind random GUIDs.** Resolve the container via `.com.apple.mobile_container_manager.metadata.plist` → `MCMMetadataIdentifier`; don't guess the directory.
- **BFU undecryptable.** Safari files are `NSFileProtectionCompleteUntilFirstUserAuthentication`. On a Before-First-Unlock device the files exist but are ciphertext — you need at least one post-boot unlock (AFU) or a passcode. See [[03-passcode-bfu-afu-and-inactivity]].
- **`CloudTabs.db` only populates with iCloud Safari sync on.** Empty doesn't mean single-device; it can mean sync off or signed out.
- **Version drift in tab schemas.** Which store holds *open* vs *closed* tabs (`SafariTabs.db` vs `BrowserState.db`) and the exact column names shifted across iOS 15→16→17→26. Always `.schema` the actual DB; don't assume.
- **The Simulator is structure-only for the device-bound pieces.** No Data Protection, no real iCloud fleet unless you sign in. Use sample images for `CloudTabs.db` realism and cleared-history scenarios.

## Key takeaways

- Safari lives at a **fixed system path** (`/private/var/mobile/Library/Safari/` + `.../Cookies/`) — no GUID hunt — across six SQLite stores plus the proprietary `Cookies.binarycookies`.
- **`History.db` = `history_items` ⋈ `history_visits`**, joined on `history_item`; `visit_time` is **Mac Absolute Time (2001)**. Search terms ride in the URL query string.
- **Tab state is spread across `SafariTabs.db` (open, iOS 16+) and `BrowserState.db` (legacy + closed)**, with the real payload in **nested, padded binary-plist BLOBs** (`local_attributes`/`extra_attributes` → `SessionState` back/forward list).
- **`RecentlyClosedTabs.plist` survives "Clear History"** — a primary anti-forensic gap; **`CloudTabs.db` enumerates the suspect's whole iCloud device fleet**.
- **`Cookies.binarycookies`** needs a dedicated parser (mixed endianness, 2001-epoch doubles); a live session cookie is **proof of account control**, stronger than a history hit.
- **Third-party browsers keep parallel cross-platform stores** in their own containers — Chrome (`urls`/`visits`, **1601 µs epoch**), Firefox (`moz_places`/`moz_historyvisits`, **1970 µs epoch**).
- **The epoch is per-file, not per-engine.** Mismatching Safari's 2001 epoch with Chromium's 1601 is the classic mixing trap — and "WebKit" in the name is a red herring.
- **Copy `*.db` + WAL/SHM, query copies only, and `.schema` before you trust any column name** — schemas drift across iOS versions.

## Terms introduced

| Term | Definition |
|---|---|
| `History.db` | Safari SQLite history store at `/private/var/mobile/Library/Safari/`; `history_items` (URLs) joined to `history_visits` (per-visit rows) |
| `history_items` / `history_visits` | The two core History.db tables: distinct URLs (+ `visit_count`) and individual timed visits (joined on `history_item`) |
| `visit_time` | History.db visit timestamp, **Mac Absolute Time** (seconds since 2001-01-01 UTC; add `978307200`) |
| Mac Absolute Time | `CFAbsoluteTime`; floating-point seconds since 2001-01-01 UTC — the epoch for Safari history and binarycookies |
| WebKit/Chrome epoch | Chromium timestamp base: microseconds since 1601-01-01 UTC (`/1e6 - 11644473600`) — *not* used by Safari despite the name |
| `SafariTabs.db` | iOS 16+ store of **currently-open tabs**; tab rows live in a `bookmarks` table with BLOB payload columns |
| `BrowserState.db` | Legacy/closed-tab store; `tabs` (private-mode flag) + `tab_sessions`; nested padded plist BLOBs |
| `local_attributes` / `extra_attributes` | Tab-store BLOB columns holding nested binary plists; `local_attributes` carries the per-tab `SessionState` back/forward list |
| `SessionState` | Per-tab serialized navigation (back/forward) list inside a tab BLOB; binary plist with leading pad bytes before `bplist00` |
| `RecentlyClosedTabs.plist` | Binary plist of recently-closed tabs that **survives "Clear History"**; excludes private tabs |
| `CloudTabs.db` | iCloud-Tabs store listing tabs open on the user's *other* signed-in devices; enumerates the Apple-account device fleet |
| `Bookmarks.db` | Safari bookmarks + Reading List (Reading List `extra_attributes` BLOB holds preview text + add/fetch dates) |
| `Cookies.binarycookies` | Apple's proprietary cookie format (`cook` magic, mixed endianness, 2001-epoch date doubles); needs a dedicated reader |
| BinaryCookieReader | Open-source Python parser for `Cookies.binarycookies` |
| `SFSafariViewController` | Hosted-Safari in-app browser; shares cookies with Safari but keeps history isolated (no `History.db` rows) |
| `WKWebView` | App-embedded web engine; its cookies/cache/storage live in the *host app's* container, not Safari's |
| `Favicons.db` | SQLite cache mapping page URLs → site icons; corroborates a visited domain and timestamps first favicon fetch |
| `Downloads.plist` | Binary plist of Safari's download manager (source URL → local path, bytes, state); ties a downloaded file to its provenance |
| `MCMMetadataIdentifier` | Key in a container's `.com.apple.mobile_container_manager.metadata.plist` mapping a random GUID dir to its app bundle ID |
| `moz_places` / `moz_historyvisits` | Firefox (incl. iOS) places-schema history tables; visit times in µs since the Unix epoch |

## Further reading

- Apple Platform Security guide (security.apple.com) — Data Protection classes governing Safari files at rest
- d204n6 (Ian Whiffin), *"iOS 16 — Breaking Down the Biomes (Part 4): Surfin' with Safari"* (blog.d204n6.com) — the definitive walkthrough of `SafariTabs.db`/`BrowserState.db` BLOB plists and `SessionState` padding
- forensafe.com, *"iOS Safari Browser"* — artifact path inventory and History.db table fields
- forensics.wiki, *Apple Safari* — store layout and the 2001-epoch float note
- `as0ler/BinaryCookieReader` (GitHub) — reference `Cookies.binarycookies` parser; Studiawan et al., *"Forensic analysis of iOS binary cookie files,"* J. Forensic Sci. (2024) for the format spec
- Alexis Brignoni, **iLEAPP** (github.com/abrignoni/iLEAPP) — Safari + third-party browser parsers for iOS extractions
- Yogesh Khatri, **mac_apt** `SAFARI` plugin (github.com/ydkhatri/mac_apt) — cross-platform (macOS + iOS) Safari parsing
- Ryan Benson, **Hindsight** (github.com/obsidianforensics/hindsight) — Chromium-family browser parsing (the iOS Chrome store is the same schema)
- RealityNet, **iOS-Forensics-References** (github.com/RealityNet/iOS-Forensics-References) — curated artifact-by-folder reference index
- Sarah Edwards (mac4n6.com), SANS FOR585 — iOS browser artifacts and timeline correlation
- Josh Hickman / Digital Corpora — public iOS reference images with multi-device CloudTabs and cleared-history scenarios
- `man sqlite3`, `man plutil` — exact flag semantics for the conversions above

---
*Related lessons: [[00-app-sandbox-and-filesystem-layout]] | [[00-the-ios-timestamp-zoo]] | [[02-bfu-vs-afu-and-data-protection-classes]] | [[01-building-a-unified-timeline]] | [[07-location-history]] | [[11-third-party-app-methodology]]*
