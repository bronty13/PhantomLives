---
title: "The app sandbox & filesystem layout"
part: "08 — Forensic Artifacts & Pattern of Life"
lesson: 00
est_time: "45 min read + 20 min labs"
prerequisites: [filesystem-layout-and-containers, the-itunes-finder-backup-format]
tags: [ios, forensics, artifacts, containers, filesystem, dfir]
last_reviewed: 2026-06-26
---

# The app sandbox & filesystem layout

> **In one sentence:** Part 08 is a tour of specific databases, but every one of them lives at the end of a path that starts with an opaque per-install UUID — so before you can parse a single artifact you have to know the iOS data model cold: the four container roots, the metadata plist that turns a GUID back into a bundle ID, the install/uninstall evidence chain (`iTunesMetadata.plist` → `applicationState.db` → MobileInstallation logs), and the per-app `Documents/Library/tmp` skeleton where the evidence actually sits.

## Why this matters

You finished [[filesystem-layout-and-containers]] knowing the *mechanism*: why iOS swaps macOS's browsable, bundle-ID-named home for opaque UUID directories, and how `containermanagerd` writes the metadata plist that resolves them. This lesson re-walks that same terrain from the **examiner's chair** — not "how does the container model work" but "I have a filesystem dump in front of me; where do I point `sqlite3`, in what order, and what proves an app was here when its directory is gone?" Every later Part-08 lesson — Messages, Photos, Safari, location, knowledgeC/Biome, Health — opens with a path, and every one of those paths hangs off the skeleton in this lesson. Get the skeleton wrong and you attribute WhatsApp's database to Signal, miss the App Group where the real evidence lives, or declare an app "never installed" because its container was torn down. Get it right and a 200-GB filesystem dump collapses into a legible inventory you can triage in minutes. This is also the map every automated tool — iLEAPP, mvt, Cellebrite Physical Analyzer, Magnet AXIOM — walks on ingest; knowing it by hand is what lets you check the tool, parse the app the tool *doesn't* support, and testify to what the tool did.

## Concepts

### The whole map on one screen

Internalize this before anything else. It is the entire Part-08 substrate, with the lesson that drills each branch:

```
/ (Data volume — /System/Volumes/Data, firmlinked to / ; see [[apfs-on-ios-volumes]])
│
├── private/var/mobile/                         ← THE USER HOME (uid 501 "mobile") — most evidence
│   │
│   ├── Library/                                ← named, macOS-style ~/Library for FIRST-PARTY stores
│   │   ├── SMS/sms.db                          → [[communications-imessage-and-sms]]
│   │   ├── CallHistoryDB/CallHistory.storedata → [[call-history-voicemail-contacts-interactions]]
│   │   ├── AddressBook/AddressBook.sqlitedb    → contacts
│   │   ├── Mail/                               → [[mail-notes-calendar-reminders]]
│   │   ├── CoreDuet/Knowledge/knowledgeC.db    → [[knowledgec-db-deep-dive]]   (legacy)
│   │   ├── Biome/streams/{public,restricted}/  → [[biome-and-segb-streams]]    (the successor)
│   │   ├── Caches/com.apple.routined/Cache.sqlite → [[location-history]]
│   │   ├── FrontBoard/applicationState.db      → install map + uninstall dates (THIS lesson)
│   │   ├── Health/healthdb*.sqlite             → [[health-and-fitness]]
│   │   ├── Preferences/  Keyboard/  Logs/CrashReporter/  Recents/  …
│   │
│   ├── Media/                                  ← the AFC area (USB-reachable, no jailbreak)
│   │   ├── DCIM/                               camera-roll originals
│   │   └── PhotoData/Photos.sqlite             → [[photos-and-the-camera-roll]]
│   │
│   └── Containers/
│       ├── Data/Application/<UUID>/            ← per-app READ-WRITE data — THIRD-PARTY evidence
│       │   └── Documents/ Library/ tmp/ SystemData/   + the metadata plist
│       └── Shared/AppGroup/<UUID>/             ← shared containers — WhatsApp/Notes DBs often HERE
│
├── private/var/containers/
│   ├── Bundle/Application/<UUID>/              ← per-app READ-ONLY signed code (.app) + iTunesMetadata
│   └── Shared/SystemGroup/<GUID>/             ← first-party daemon shared state (Wi-Fi, profiles, Find My)
│
├── private/var/installd/Library/Logs/MobileInstallation/   ← install/uninstall/update LOG timeline
├── private/var/Keychains/keychain-2.db        ← device keychain (outside every container) → [[keychain-on-ios]]
└── private/var/keybags/                       ← Data-Protection keybags (NOT /Keychains) → [[data-protection-and-keybags]]
```

Two asymmetries trip up everyone and both are load-bearing for an examiner:

1. **Read-write app data is under `/private/var/mobile/Containers/`; read-only app code is under `/private/var/containers/`** (no `mobile`). Two different roots, one word apart.
2. **First-party apps mostly kept the named `~/Library` tree; third-party apps live in UUID containers.** An iOS image is a *hybrid* — a legible OS area and an opaque app area — so "Apple app ⇒ named path, third-party ⇒ UUID" is a useful default but not a rule (newer Apple apps moved into containers too). Resolve, don't assume.

> 🖥️ **macOS contrast:** On macOS you found an app's data at `~/Library/Application Support/<App>/` — the directory name *was* the answer (a bundle ID or a human app name), self-documenting, browsable, and stable across reinstalls. iOS deletes that affordance for every third-party app: the data lives at `…/Data/Application/0F3A…D21C/`, a per-install random UUID that means nothing until you read its metadata plist. The single biggest reflex you must unlearn from `macos-mastery` is "I can `ls` the container tree and read off who owns what." On iOS, `ls` of the container tree is a list of GUIDs; **attribution is a separate, mandatory first step.**

### Step one of every app exam: resolve UUID → bundle ID

The mechanism is in [[filesystem-layout-and-containers]] — here is the *operational* version. Four container roots, each carrying a hidden `.com.apple.mobile_container_manager.metadata.plist` at its root whose `MCMMetadataIdentifier` key is the authoritative, offline, local bundle/group ID for that directory:

```
ROOT                                                    MCMMetadataIdentifier resolves to
─────────────────────────────────────────────────────  ────────────────────────────────────
/private/var/containers/Bundle/Application/<UUID>/      a bundle ID   (read-only code)
/private/var/mobile/Containers/Data/Application/<UUID>/ a bundle ID   (read-write data + extensions)
/private/var/mobile/Containers/Shared/AppGroup/<UUID>/  a group ID    (group.*)
/private/var/containers/Shared/SystemGroup/<GUID>/      a system group ID (systemgroup.*)
```

Sweep all four, read each metadata plist, build one join table — `UUID ↔ identifier ↔ content-class ↔ root` — and group an app's bundle UUID, data UUID, extension UUIDs, and group UUIDs under one identifier stem. That table is the lookup every subsequent path resolves through. The hard-won examiner rule: **correlate on `MCMMetadataIdentifier`, never on the UUID** — UUIDs are per-install, per-role, and regenerate on reinstall, so they are meaningless across two acquisitions of the same device (let alone across devices).

> 🔬 **Forensics note:** You do not have to read thousands of metadata plists by hand to get the map — iOS keeps a consolidated index in `applicationState.db` (next section) and the tools build the join automatically. But the metadata plist is the **ground truth that survives when the index doesn't**: it is local, offline, and present even on a partial dump where `applicationState.db` is missing or locked. When a tool's container map and the raw plists disagree, the plist wins — and the disagreement itself is worth noting (a copied-in or tampered container manifests as a `MCMMetadataUUID` that doesn't match its own directory name).

### The install/uninstall evidence chain

"Was this app ever on the device, and when?" is a question the live container tree answers badly: a present container says "installed now," and a *missing* container says nothing — uninstall tears down the Bundle/Data/Group directories and they vanish. Three artifacts, in increasing order of how hard they are to scrub, carry the history:

**1. `iTunesMetadata.plist` — attribution (in the Bundle container).** For App Store apps this binary plist (at the root of `/private/var/containers/Bundle/Application/<UUID>/`) records the **purchasing Apple ID** and the download event:

| Key (path) | What it proves |
|---|---|
| `com.apple.iTunesStore.downloadInfo` → `accountInfo` → `AppleID` | the iCloud account that bought/downloaded the app |
| `com.apple.iTunesStore.downloadInfo` → `accountInfo` → `DSPersonID` | the numeric Apple directory-services account ID (stable, survives email changes) |
| `itemName`, `genre`, `bundleShortVersionString`, `softwareVersionBundleId` | the app's identity and version at install |
| `purchaseDate` / download-date fields | when this copy landed on this device |

This ties an installed app to a specific account even when the app's own data container is empty — answering "whose device is this?" and flagging apps **sideloaded under a different Apple ID** than the rest. (It exists only for App Store apps; sideloaded/enterprise/dev builds carry an `embedded.mobileprovision` instead — the inverse tell, covered in [[filesystem-layout-and-containers]].)

**2. `applicationState.db` — the consolidated install map + uninstall dates.** This is the single most useful "what apps, where, and were any removed" file on the device. It is a SQLite database; **its location moved in iOS 18** (verify against your image's OS version):

```
iOS 10–17:  /private/var/mobile/Library/FrontBoard/applicationState.db
iOS 18+  :  /private/var/mobile/FrontBoard/applicationState.db      ← the Library/ segment was dropped
```

Three tables matter, and the schema is non-obvious because it is a **normalized key-value store**, not a flat row-per-app table:

| Table | Role |
|---|---|
| `application_identifier_tab` | `id` ↔ `application_identifier` (the bundle ID). One row per app FrontBoard has ever tracked. |
| `key_tab` | `id` ↔ `key` (a string key name like `compatibilityInfo`, `_UninstallDate`, `XBApplicationSnapshotManifest`). |
| `kvs` | the value store: `(application_identifier, key, value)` where `value` is a **binary-plist BLOB**. |

The catch that burns people: **the integer in `key_tab.id` is assigned per device** — `compatibilityInfo` might be key `1` on one phone and `7` on another. You **must JOIN through `key_tab` by the string name**, never hardcode an integer. Two BLOB values carry the gold:

- **`compatibilityInfo`** — a binary plist that embeds the app's **bundle-container path and data-container (sandbox) path**. This is the same UUID → path mapping you'd rebuild from the scattered metadata plists, consolidated and queryable in one file. It is how you find the obscure GUID directory for an app the vendor tool didn't parse.
- **`_UninstallDate`** — an `NSDate`. Its *presence* means FrontBoard recorded the app being removed, and the date is *when*. An app with a `_UninstallDate` whose container is gone is provable "was installed, then deleted, at this time."

> 🔬 **Forensics note:** `applicationState.db` is the fastest route from a bundle ID to its on-disk container path *and* a deleted-app timeline in one query. The `XBApplicationSnapshotManifest` key (third high-value BLOB) inventories the **app-switcher snapshot images** — the cached screenshots iOS takes when you background an app — and points at where they live on disk. Those snapshots can recover *what an app last displayed* even when the app's own data is locked or wiped: a banking balance, a message thread, a photo. Always pull the snapshot manifest and the snapshot files together.

**3. MobileInstallation logs — the install/update/uninstall *timeline*.** `installd` writes a rotated text log of every install, update, and removal it performs:

```
iOS 10+:  /private/var/installd/Library/Logs/MobileInstallation/mobile_installation.log.N
          (.0 is newest; older versions used /private/var/mobile/Library/Logs/MobileInstallation/)
```

Each line carries a timestamp and the bundle ID, and update lines show the **previous and new version numbers** — so these logs reconstruct "app X installed at T1, updated to v2 at T2, uninstalled at T3, reinstalled at T4," including reboot events for anchoring. The limitation is retention: the logs rotate and may not reach back far, so they corroborate rather than guarantee. When they *do* cover the window, they are the cleanest install/uninstall chronology iOS keeps in plaintext.

> 🔬 **Forensics note:** Triangulate the three. `iTunesMetadata.plist` says *who* and roughly *when first acquired*; `applicationState.db._UninstallDate` says *when removed*; the MobileInstallation logs give the *full install/update/reinstall sequence with timestamps*. Add the pattern-of-life stores ([[biome-and-segb-streams]], [[knowledgec-db-deep-dive]]) and the SpringBoard icon layout (`com.apple.springboard` / `IconState`) and you can place a since-deleted app on the device, name it, and time its lifecycle — none of which the absent container alone could do. "Container gone" ≠ "app never there."

### Where the artifacts actually live: the Data container, ranked by yield

Once you've resolved a third-party app to its Data container, the evidence sits in the familiar `Documents/Library/tmp/SystemData` skeleton — but not uniformly. Rank your triage by where apps actually persist things, and by whether the location even survives into a backup (which decides whether you can see it without a full-filesystem extraction):

| Path (under the Data container) | What's there | In an iTunes/Finder backup? | Notes |
|---|---|---|---|
| `Documents/` | the app's primary store — very often its main SQLite DB | **Yes** | first place to look; `*.sqlite`, `*.db`, Core Data stores |
| `Documents/Inbox/` | files opened *into* the app from elsewhere | Yes | provenance — a file the user received/imported |
| `Library/Application Support/` | app-managed persistent data, secondary DBs | Yes | second SQLite store often hides here |
| `Library/Preferences/<bundleid>.plist` | `NSUserDefaults` | Yes | settings, account hints, last-used state, feature flags |
| `Library/Caches/` | regenerable caches | **No — excluded from backups** | retains "deleted-from-UI" data; visible only in an FFS |
| `Library/Cookies/Cookies.binarycookies` | per-app HTTP cookies (binary, not SQLite) | Yes | session/auth artifacts |
| `Library/WebKit/`, `Library/Caches/WebKit/` | embedded `WKWebView` state (LocalStorage, IndexedDB) | partial | in-app browser history/data |
| `Library/SplashBoard/` | launch-storyboard snapshots | No | last-screen imagery on app switch |
| `tmp/` | scratch, purged aggressively | No | occasional deleted-file window |

The single most consequential row is `Library/Caches/`: **it is not in the backup, so it never appears in a logical/backup acquisition — only in a full-filesystem extraction.** A huge fraction of "the suspect deleted it but we recovered it" wins come from `Caches/`, because apps stage and cache content there that the UI and the backed-up databases no longer reference.

> 🔬 **Forensics note:** The backup-inclusion column is an acquisition-method decision, not trivia. If your only lawful acquisition is an encrypted iTunes/Finder backup (see [[the-itunes-finder-backup-format]]), you will **never** see `Caches/`, `tmp/`, or `SplashBoard/` — the backup daemon honors each file's "do not back up" exclusion. Knowing a target artifact lives in `Caches/` tells you up front that a backup won't reach it and you need a full-filesystem extraction ([[full-file-system-acquisition]]) — or it's simply unrecoverable by the means you have. Decide the acquisition method *from* where the artifact lives.

### The trap: the real evidence is often in the App Group, not the app's container

This is the error that makes examiners declare a chat app "empty." An app and its extensions are separate processes with separate Data containers; the sanctioned shared channel is an **App Group** (`/private/var/mobile/Containers/Shared/AppGroup/<UUID>/`), and many apps put their primary database *there* so an extension can read it:

```
com.whatsapp.WhatsApp  →  ChatStorage.sqlite        lives in  group.net.whatsapp.WhatsApp.shared
com.apple.mobilenotes  →  NoteStore.sqlite          lives in  group.com.apple.notes
(many apps)            →  the Core Data store        lives in  group.<app>.shared
```

The App Group's metadata plist resolves its UUID to a **group identifier** (`group.*`), not a bundle ID. If your triage only enumerates `Data/Application/<UUID>` containers, you miss every one of these. The authoritative app → group(s) mapping lives in the app's **embedded entitlements** (`com.apple.security.application-groups`, carried in the `.app`'s code signature / `embedded.mobileprovision`); enumerating `Shared/AppGroup/` gives you the group IDs (each container's `MCMMetadataIdentifier`), and the entitlement is what ties each `group.*` back to its owning app. iLEAPP/Cellebrite/Magnet do this join automatically — but when you work by hand, **always enumerate `Shared/AppGroup/` too, and join groups to their owning app by entitlement.**

> 🔬 **Forensics note:** A thin or empty Data container for a messaging or notes app is a *signal to check the App Group*, not evidence the app is unused. Conversely, App Extensions (Share, Notification Service, custom keyboards) are PluginKit plugins with their *own* Data containers resolving to *different* bundle IDs (typically the host ID plus a suffix, e.g. `com.whatsapp.WhatsApp.ShareExtension`) — a third place an app can leave traces that a host-only triage skips.

### The same artifact, two address spaces: FFS path vs backup domain

Everything above is the **full-filesystem (FFS)** address space — real `/private/var/...` paths. But a large fraction of lawful iOS acquisition is an **iTunes/Finder backup**, and a backup does *not* preserve those paths. It re-addresses every file through `Manifest.db` (see [[the-itunes-finder-backup-format]]): a `Files` table whose columns are `fileID` (the SHA‑1 of `"<domain>-<relativePath>"`), `domain`, `relativePath`, and a `file` BLOB plist of metadata. The bytes are stored as a flat blob at `<backup>/<first-2-hex-of-fileID>/<fileID>` — **no directory structure on disk at all.** So the same database has two completely different addresses depending on how you acquired it, and translating between them is a routine examiner skill:

| Artifact | FFS path | Backup domain + relativePath |
|---|---|---|
| iMessage/SMS | `/private/var/mobile/Library/SMS/sms.db` | `HomeDomain` + `Library/SMS/sms.db` |
| Photos catalog | `/private/var/mobile/Media/PhotoData/Photos.sqlite` | `CameraRollDomain` + `Media/PhotoData/Photos.sqlite` |
| Third-party app DB | `…/Data/Application/<UUID>/Documents/Store.sqlite` | `AppDomain-com.foo.Bar` + `Documents/Store.sqlite` |
| App-Group DB | `…/Shared/AppGroup/<UUID>/ChatStorage.sqlite` | `AppDomainGroup-group.net.whatsapp.WhatsApp.shared` + `ChatStorage.sqlite` |
| Extension data | `…/Data/Application/<UUID>/…` (plugin's container) | `AppDomainPlugin-com.foo.Bar.Share` + `…` |

The crucial inversion: in the backup, **the opaque UUID disappears** — the domain string `AppDomain-<bundleid>` / `AppDomainGroup-<groupid>` *is* the bundle/group ID, so the attribution problem the FFS forces on you (resolve UUID → bundle) is already solved by the domain name. The trade is that the backup omits whatever the file's "do not back up" flag excluded — so `AppDomain-*` domains carry `Documents/` and `Library/Preferences/` but **not** `Library/Caches/` or `tmp/`. The `relativePath` inside an `AppDomain` is relative to that app's Data-container root, which is exactly the per-app skeleton from the yield table above.

> 🖥️ **macOS contrast:** A macOS Time Machine backup is just a copy-on-write APFS snapshot — files keep their real paths, so you browse `Backups.backupdb/<Mac>/<date>/.../Users/you/Library/...` exactly as on the live disk. An iOS backup throws the path tree away and re-keys every file by `SHA‑1(domain-relativePath)` into a flat fan-out, with `Manifest.db` as the only index. There is nothing to `cd` into — you query `Manifest.db` for the `fileID`, then open the blob by its hash. The mental shift from "browse a path tree" to "look up a hash in a manifest" is the macOS-reflex this breaks.

> 🔬 **Forensics note:** Always know which address space your evidence is in *before* you cite a path in a report. "`sms.db` at `HomeDomain/Library/SMS/sms.db`" is a backup citation; "`sms.db` at `/private/var/mobile/Library/SMS/sms.db`" is an FFS citation; they describe the same artifact from two acquisitions. iLEAPP and mvt accept both and normalize internally, but your notes must record which one you actually parsed — and remember that an `AppDomain-*` backup silently lacks `Caches/`, so an artifact "missing" from a backup may be present in an FFS of the same device.

### The named first-party tree and the Media partition — recap for the hunt

Two areas don't follow the UUID-container model and you target them by fixed path:

- **`/private/var/mobile/Library/`** — the named, `~/Library`-style tree where first-party stores live: `SMS/sms.db`, `CallHistoryDB/`, `AddressBook/`, `Mail/`, `CoreDuet/Knowledge/knowledgeC.db`, `Biome/streams/`, `Caches/com.apple.routined/`, `FrontBoard/applicationState.db`, `Health/`, `Preferences/`, `Keyboard/`, `Logs/CrashReporter/`, `Recents/`. This is the index every Part-08 first-party lesson hits directly — no UUID resolution needed.
- **`/private/var/mobile/Media/`** — the **AFC-exposed** partition: `DCIM/` (camera-roll originals) and `PhotoData/Photos.sqlite` (the Photos catalog — [[photos-and-the-camera-roll]]). This is the one app-data-rich area reachable over USB on an *unlocked* device with **no jailbreak**, via Apple File Conduit (`afcclient`/`ifuse`/`pymobiledevice3 afc`), which makes DCIM + `Photos.sqlite` one of the cheapest high-value pulls in [[logical-acquisition-with-libimobiledevice]]. App containers under `Containers/` are **not** in AFC's view.

### How the tools walk this map (so you can check them)

iLEAPP and mvt are not magic — they mechanize exactly the workflow above, and knowing the steps lets you verify their output and parse what they skip:

```
INGEST a filesystem dump / backup
  │
  ├─ 1. Sweep the four container roots; read every .com.apple.mobile_container_manager.metadata.plist
  │      → build UUID ↔ MCMMetadataIdentifier ↔ content-class ↔ root  (the join table)
  │
  ├─ 2. Cross-check against applicationState.db (compatibilityInfo paths, _UninstallDate)
  │      and the MobileInstallation logs  → installed/uninstalled/updated timeline
  │
  ├─ 3. Map App Groups to owning apps via entitlements; fold extensions in by bundle-ID suffix
  │
  └─ 4. For each KNOWN artifact (sms.db, Photos.sqlite, an app's Documents/*.sqlite, …),
         resolve its container path through the join table and run the parser module.
```

- **iLEAPP** (Brignoni, `github.com/abrignoni/iLEAPP`) ingests a full-filesystem extraction (`-t fs`), a tar/zip, or a backup, and has dedicated modules for installed-applications / container resolution, `applicationState.db`, and the App-Group/metadata-plist mapping. It emits an HTML/SQLite report. Its "Installed Applications" output *is* the join table you'd build by hand.
- **mvt** (Mobile Verification Toolkit, `mvt-ios`) targets backups (`check-backup`, `decrypt-backup`) and filesystem dumps (`check-fs`); it enumerates installed apps and runs IOC-driven checks, and is the standard tool for spyware triage (Pegasus/Predator indicators) on top of the same layout.

> 🔬 **Forensics note:** The reason to know the manual walk is the app the tool *doesn't* support. A vendor parser covers the common apps; an obscure or new app (or one renamed to evade) won't have a module. The skill that matters is: resolve its container via `applicationState.db.compatibilityInfo`, open its `Documents/` and `Library/Application Support/`, recognize the SQLite/plist/Core Data stores, and parse them yourself. The tools handle breadth; you handle the long tail and the verification.

### The first ten minutes: a triage order

Given a fresh filesystem dump and the map above, the productive order of operations is not "open random containers." Work the skeleton top-down, cheapest-and-broadest first:

```
 1. Build the inventory.   applicationState.db (compatibilityInfo) + the four metadata-plist roots
                           → the UUID↔bundle↔path join table. Everything else resolves through it.
 2. Establish presence.    MobileInstallation logs + _UninstallDate + iTunesMetadata accountInfo
                           → which apps, whose account, installed/removed when.
 3. Hit the named tree.    /private/var/mobile/Library/{SMS,CallHistoryDB,Mail,Biome,knowledgeC,
                           routined,Health} — fixed paths, no resolution, high yield, OS-managed.
 4. Pull the Media area.   Media/PhotoData/Photos.sqlite + DCIM (also the cheapest live-device pull).
 5. Resolve targets.       For each app of interest, its Data container Documents/ + Library/Application
                           Support/, THEN its App Group, THEN its plugins. Don't stop at the host.
 6. Mine the cache tier.   Library/Caches/, tmp/, SplashBoard/ — FFS-only, where "deleted" content hides.
```

Steps 1–2 are attribution and presence and they gate everything; steps 3–4 are fixed-path, no-resolution wins you can grab immediately; steps 5–6 are the per-app deep dive. Running them out of order — diving into an app container before you've built the join table — is how examiners burn time in the wrong GUID directory or, worse, attribute a file to the wrong app.

> 🔬 **Forensics note:** This order is also a *defensibility* order. Steps 1–2 produce the inventory and timeline you'll put at the front of the report and that every later finding hangs off; doing them first means every subsequent path you cite is already resolved and attributable. If you jump straight to "interesting" content, you may later have to re-derive the attribution for the exact file you care about — under cross-examination, after the fact, which is the worst time to discover the container resolved to a different bundle ID than you assumed.

### The lock-state caveat on the entire map

Everything above is *structure*. Whether you can read a given file's *contents* depends on its Data-Protection class and the device's lock state (BFU vs AFU — [[passcode-bfu-afu-and-inactivity]], [[bfu-vs-afu-and-data-protection-classes]]). The container **layout** — directory names, metadata plists, `applicationState.db` — is mostly low-protection metadata you can enumerate even on a locked device whose evidence files stay encrypted. So you can often rebuild the full app inventory and container map of a **BFU** device while its actual databases remain unreadable. Mapping the containers is not reading the data; keep the two claims separate in your report.

## Hands-on

There is no on-device shell. The Simulator stores the *same* container layout **unencrypted on the Mac** (no `/private` prefix, no encryption, no SEP), which is the right place to drill the resolution-and-triage workflow; device-only stores come from sample images. See [[simulator-internals-and-on-disk-filesystem]] for the Simulator's on-disk shape.

### Build the container map and resolve one app (Simulator)

```bash
# Booted simulator's container root (the device-side /private/var/mobile/Containers analogue):
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
CTN=~/Library/Developer/CoreSimulator/Devices/$DEV/data/Containers

# The cleanest one-shot UUID→bundle map — both container paths per app:
xcrun simctl listapps booted | plutil -p - | grep -E 'CFBundleIdentifier|DataContainer|Bundle ' | head -40

# Resolve a single bundle ID straight to each of its containers:
xcrun simctl get_app_container booted com.apple.mobilesafari data
xcrun simctl get_app_container booted com.apple.mobilesafari app
xcrun simctl get_app_container booted com.apple.mobilesafari groups

# Now do it the device-truth way — read each Data container's metadata plist by hand:
for d in "$CTN"/Data/Application/*/; do
  id=$(plutil -extract MCMMetadataIdentifier raw \
        "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null)
  printf '%s\t%s\n' "$(basename "$d")" "$id"
done
#   0F3A…D21C   com.apple.mobilesafari
#   7C19…A4B2   com.apple.MobileSMS
```

### Inventory one app's artifact-bearing directories (Simulator)

```bash
APP=$(xcrun simctl get_app_container booted com.apple.mobilesafari data)
# Where do artifacts live? Show the skeleton and find the SQLite/plist stores:
find "$APP" -maxdepth 2 -type d | sort
ls -la "$APP/Documents" "$APP/Library/Preferences" "$APP/Library/Caches" 2>/dev/null

# Find every SQLite store in the container (the parse targets):
find "$APP" -type f \( -name '*.sqlite' -o -name '*.db' -o -name '*.sqlitedb' \) 2>/dev/null

# Read the preferences plist (binary → text; grep on a binary plist returns nothing useful):
plutil -p "$APP/Library/Preferences/com.apple.mobilesafari.plist" 2>/dev/null | head -30
```

### Query `applicationState.db` (against a sample image's copy)

```bash
# COPY before query — even SELECT takes a write lock and spawns -wal/-shm sidecars:
cp "<image_root>/private/var/mobile/FrontBoard/applicationState.db" /tmp/appstate.db   # iOS 18+ path
# (iOS 10–17: .../private/var/mobile/Library/FrontBoard/applicationState.db)

# JOIN through key_tab by STRING name — the integer key id is per-device, never hardcode it:
sqlite3 /tmp/appstate.db "
SELECT ait.application_identifier AS bundle_id,
       kt.key                     AS key_name,
       length(kvs.value)          AS blob_bytes
FROM kvs
JOIN application_identifier_tab ait ON kvs.application_identifier = ait.id
JOIN key_tab kt                     ON kvs.key = kt.id
WHERE kt.key IN ('compatibilityInfo','_UninstallDate','XBApplicationSnapshotManifest')
ORDER BY bundle_id;
"
#   com.burner.app   _UninstallDate            42     ← app was uninstalled; date is in the BLOB
#   com.burner.app   compatibilityInfo        318
#   com.foo.Bar      compatibilityInfo        402

# The value column is a BINARY PLIST BLOB — sqlite3 shows gibberish. Extract & parse it:
sqlite3 /tmp/appstate.db "
SELECT writefile('/tmp/compat.plist', kvs.value)
FROM kvs JOIN application_identifier_tab ait ON kvs.application_identifier = ait.id
         JOIN key_tab kt ON kvs.key = kt.id
WHERE ait.application_identifier='com.foo.Bar' AND kt.key='compatibilityInfo';"
plutil -p /tmp/compat.plist        # → embeds the bundle + data container paths for com.foo.Bar
```

### Find an artifact in a backup's address space (Manifest.db)

```bash
# A Finder/iTunes backup has NO path tree — query Manifest.db for the fileID, then open the blob.
cp "<backup_dir>/Manifest.db" /tmp/manifest.db        # decrypt the backup first if encrypted
sqlite3 /tmp/manifest.db "
SELECT domain, relativePath, fileID
FROM Files
WHERE relativePath LIKE '%sms.db'
   OR (domain LIKE 'AppDomainGroup-%' AND relativePath LIKE '%ChatStorage.sqlite');
"
#   HomeDomain                                   Library/SMS/sms.db        3d0d7e5f...
#   AppDomainGroup-group.net.whatsapp.WhatsApp.shared  ChatStorage.sqlite  a1b2c3d4...

# The bytes live at <backup>/<first 2 hex of fileID>/<fileID> — copy it out by hash:
cp "<backup_dir>/3d/3d0d7e5f..." /tmp/sms.db && sqlite3 /tmp/sms.db .tables
```

### Let the tools walk it, then verify (sample image)

```bash
# iLEAPP against an extracted filesystem dump:
python3 ileapp.py -t fs -i <extracted_root> -o /tmp/ileapp_out
#   open /tmp/ileapp_out/*/index.html → "Installed Applications" = the join table; compare to your hand map.

# mvt-ios against a (decrypted) backup or fs dump:
mvt-ios check-fs <extracted_root> --output /tmp/mvt_out      # enumerates apps + runs IOC checks
mvt-ios decrypt-backup -p '<password>' -d /tmp/dec <backup_dir>   # then check-backup /tmp/dec
```

## 🧪 Labs

### Lab 1 — The artifact-yield map of one app (Substrate: iOS Simulator)

**Substrate & fidelity:** CoreSimulator on your Mac. Container *layout and the Documents/Library/tmp skeleton are byte-faithful to a device*; what's absent is encryption/Data-Protection, SEP, FairPlay (`SC_Info/`), and the device-only pattern-of-life daemons (`knowledged`, `biomed`, `routined`, `powerlogHelperd`). This teaches *where artifacts live and how to find them*, not lock-state or pattern-of-life.

1. Boot a simulator and exercise two apps so they write data: open Safari and visit a few sites; create a note in Notes.
2. For Safari, resolve its Data container (`xcrun simctl get_app_container booted com.apple.mobilesafari data`) and inventory it: enumerate `Documents/`, `Library/Preferences/`, `Library/Caches/`, `Library/WebKit/`. Use the `find … -name '*.sqlite'` command from Hands-on to locate the actual SQLite stores.
3. For *each* store you found, write down which directory it sits in and predict — from the yield table — whether it would survive into an iTunes/Finder backup. (`Caches/` won't; `Documents/` and `Library/Application Support/` will.)
4. List Safari's `groups`; if any resolve to a `group.*` ID, open the App Group container and check whether a store lives there too. Note that you just located evidence the host container alone wouldn't show.

### Lab 2 — The install/uninstall evidence chain (Substrate: public sample image, read-only)

**Substrate & fidelity:** a full-filesystem reference image (Josh Hickman's iOS image from thebinaryhick.blog / Digital Corpora). This is a *real device* layout with `applicationState.db`, MobileInstallation logs, and `iTunesMetadata.plist` populated — the things the Simulator can't faithfully produce. Work on copies; `cp` every SQLite before `sqlite3`.

1. Find `applicationState.db` (check both the iOS 18+ `FrontBoard/` path and the legacy `Library/FrontBoard/` path — note which your image uses, and record it as a version fact). Copy it, then run the three-table JOIN from Hands-on.
2. Filter for rows where `key_name = '_UninstallDate'`. For one such app, extract the BLOB with `writefile` and `plutil -p` it to read the uninstall `NSDate`. You have now proven an app was installed and removed, with a timestamp, on a device where its container no longer exists.
3. Extract a `compatibilityInfo` BLOB for an app whose container *does* still exist; confirm the container path inside the plist matches the actual `Data/Application/<UUID>` directory on the image.
4. Locate `private/var/installd/Library/Logs/MobileInstallation/mobile_installation.log.0`, find install/update/uninstall lines for that same app, and reconcile the timeline with the `_UninstallDate`. Where they overlap, do the timestamps agree?
5. Pick one App Store app and read its Bundle-container `iTunesMetadata.plist` (`plutil -p`); record the `AppleID`/`DSPersonID` under `downloadInfo → accountInfo`. Does every app resolve to the *same* purchasing account, or is one sideloaded under a different ID?

### Lab 3 — Tool-vs-hand container map (Substrate: public sample image, read-only)

**Substrate & fidelity:** same image as Lab 2.

1. Run iLEAPP against the extracted root (`python3 ileapp.py -t fs -i <root> -o out`). Open the report's "Installed Applications" / container-resolution section.
2. Independently, hand-resolve three `Data/Application/<UUID>` directories via their metadata plists (the loop from Hands-on). Confirm your three UUID→bundle rows appear identically in iLEAPP's output.
3. Pick one app iLEAPP lists and navigate to its container *by hand* using the path iLEAPP gives. Open its `Documents/` and `Library/Application Support/`, identify the SQLite stores, and `cp`-then-`sqlite3 .tables` one of them — proving you can parse a target the tool resolved but you read yourself.
4. (Optional) Run `mvt-ios check-fs <root>` and compare its installed-apps enumeration to iLEAPP's and to your hand map. Three independent walks of the same skeleton should agree.

### Lab 4 — What a backup vs an FFS can reach (Substrate: read-only walkthrough + Simulator stand-in)

**Substrate & fidelity:** narration of the acquisition gate + a Simulator stand-in for the parsing skill. No device required.

1. On paper, classify each target by which acquisition *exposes* it: an app's `Documents/Store.sqlite` (backup ✅ + FFS ✅), `Library/Caches/` (backup ❌, **FFS only**), `tmp/` (backup ❌), `DCIM/` + `PhotoData/Photos.sqlite` (AFC ✅, unlocked, no jailbreak), an arbitrary app's full `Library/` (❌ logical — needs FFS), `keychain-2.db` secrets (❌ — FFS *and* a decryption agent).
2. State the consequence: if your only lawful acquisition is an encrypted backup, which Lab-1 stores would you *never* see? (Everything in `Caches/`, `tmp/`, `SplashBoard/`.)
3. In the Simulator, prove the *parsing* half is identical regardless of acquisition: pull one app's `Documents/*.sqlite` and the simulated `Photos.sqlite`, `cp`, and `sqlite3 .schema`. The acquisition gate differs by method; the parse does not.

### Lab 5 — Translate FFS paths into backup domains (Substrate: public sample backup, read-only)

**Substrate & fidelity:** a decrypted iTunes/Finder backup of a reference device (Hickman's images ship paired backups; or make one from the Simulator-adjacent tooling). No physical device; you parse a `Manifest.db`. The address-space translation is identical to a real-case backup.

1. `cp Manifest.db` and run `sqlite3 manifest.db ".tables"`; confirm the `Files` table with `domain` / `relativePath` / `fileID`.
2. For three FFS artifacts you found in Lab 2 (e.g. `sms.db`, an app's `Documents/Store.sqlite`, an App-Group DB), write the backup query that locates each by `domain` + `relativePath`. Confirm the `AppDomain-<bundleid>` / `AppDomainGroup-<groupid>` domain string *is* the bundle/group ID — the UUID is gone.
3. Pick one app and query for any `relativePath LIKE 'Library/Caches/%'` in its `AppDomain`. Confirm there are **none** — the backup excluded the cache tier — and state what acquisition you'd need to recover it.
4. Copy one blob out by its `fileID` fan-out path (`<backup>/<2 hex>/<fileID>`) and `sqlite3 .tables` it, proving the hash-addressed blob is the real database.

## Pitfalls & gotchas

- **`ls` of the container tree is a list of GUIDs, not apps.** Attribution via `MCMMetadataIdentifier` is a mandatory first step, not an optional nicety. Skipping it is how one app's evidence gets attributed to another.
- **The two container roots have different parents.** Read-write data is `/private/var/mobile/Containers/…`; read-only code is `/private/var/containers/…` (no `mobile`). One word apart, easy to fat-finger into the wrong tree.
- **`applicationState.db` moved in iOS 18.** It is `…/mobile/FrontBoard/applicationState.db` on iOS 18+, `…/mobile/Library/FrontBoard/applicationState.db` on iOS 10–17. Check both paths against your image's OS version and *record which one you found* — it's a small but real version fact.
- **`key_tab.id` is per-device.** `compatibilityInfo` is not always key 1. JOIN `kvs` → `key_tab` by the *string* name; hardcoding the integer silently reads the wrong values on the next device.
- **`kvs.value` is a binary-plist BLOB.** `sqlite3` prints gibberish for it. `writefile` it out (or use a plist-aware tool) and `plutil -p`; the container paths and uninstall dates are *inside* the BLOB, not in the SQL columns.
- **The real evidence is frequently in the App Group, not the Data container.** WhatsApp's `ChatStorage.sqlite` and Notes' `NoteStore.sqlite` live under `Shared/AppGroup/<UUID>`. Enumerate group containers and join them to the owning app by entitlement, or you'll call a busy app "empty."
- **`Caches/` and `tmp/` are not in backups.** A backup-only acquisition cannot see them — yet they hold a disproportionate share of recoverable "deleted" content. Decide your acquisition method *from* where the target artifact lives.
- **A missing container is not proof of absence.** Uninstall removes the directory but leaves `_UninstallDate` in `applicationState.db`, lines in the MobileInstallation logs, usage in Biome/knowledgeC, and entries in old backups. Date your inventory to the acquisition, not to "now."
- **A present app *with* a `_UninstallDate` means it was deleted and reinstalled.** Reinstalling mints a fresh container UUID, so a currently-installed app whose `applicationState.db` row still carries an `_UninstallDate` is evidence of a prior delete→reinstall cycle — and the current container will *not* hold data the pre-deletion install wrote (look for it in older backups instead). Don't read `_UninstallDate` as "not installed"; read it as "was removed at least once."
- **Copy SQLite before you query.** A `SELECT` on `applicationState.db`/`sms.db`/`Photos.sqlite` takes a write lock and spawns `-wal`/`-shm` sidecars — on an evidence image that *alters the artifact*. `cp` first, every time.
- **Binary plists are not text.** `grep` on a metadata plist or `iTunesMetadata.plist` returns nothing useful; `plutil -p` / `-convert xml1` / `-extract … raw` first.
- **Layout legibility ≠ data readability.** You can often map the whole container tree on a BFU device while the databases stay encrypted. "I built the container map" and "I read the evidence" are different claims — keep them separate in the report.
- **Simulator fidelity stops at structure.** No encryption, no Data-Protection, no FairPlay `SC_Info/`, and `applicationState.db`/Biome/`routined` don't populate device-style stores. Drill *layout and resolution* in the Simulator; use a sample image for the install/uninstall chain and anything lock-state-dependent.

## Key takeaways

- Part 08 is a sequence of "go to *this* path, parse *this* database," and every path starts at the skeleton in this lesson — the four container roots plus the named `/private/var/mobile/Library` tree and the `/private/var/mobile/Media` AFC area.
- **Step one of every app exam is UUID → bundle-ID resolution** via each container's `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`); correlate on the bundle ID, never on the per-install UUID.
- The **install/uninstall evidence chain** is `iTunesMetadata.plist` (purchasing Apple ID + version), `applicationState.db` (consolidated container-path map via `compatibilityInfo` + `_UninstallDate` + snapshot manifest), and the MobileInstallation logs (the install/update/uninstall *timeline*) — triangulate all three.
- `applicationState.db` is a **normalized key-value store** (`application_identifier_tab` + `kvs` + `key_tab`); JOIN through `key_tab` by string name because the key integer is per-device, and its location **moved out of `Library/` in iOS 18**.
- Within a Data container, rank triage by yield and by **backup inclusion**: `Documents/` and `Library/Application Support/` are in backups; `Library/Caches/` and `tmp/` are **not** — so a backup-only acquisition can't see them.
- **The real database is often in the App Group**, not the app's own Data container — enumerate `Shared/AppGroup/` and join groups to apps by entitlement, or you'll declare a busy app empty.
- A **missing container is not proof of absence**: `_UninstallDate`, install logs, Biome, icon-state, and old backups all outlive the deleted directory.
- The **same artifact has two addresses**: an FFS `/private/var/...` path and a backup `Manifest.db` domain (`AppDomain-<bundleid>` etc., where the domain *is* the bundle ID and the UUID disappears) — cite which acquisition you parsed, and remember backups omit `Caches/`/`tmp/`.
- iLEAPP and mvt mechanize exactly this walk; knowing it by hand lets you **verify the tool and parse the app the tool doesn't support**.
- **Mapping the containers is not reading the data** — layout is enumerable even on a BFU device whose contents stay encrypted; keep the two claims distinct.

## Terms introduced

| Term | Definition |
|---|---|
| `applicationState.db` | FrontBoard SQLite (a normalized KVS) mapping bundle IDs to container paths and recording uninstall dates + the app-switcher snapshot manifest; at `/private/var/mobile/FrontBoard/` on iOS 18+, `…/Library/FrontBoard/` on iOS 10–17 |
| `application_identifier_tab` | `applicationState.db` table linking an internal `id` to each app's bundle ID (`application_identifier`) |
| `kvs` | `applicationState.db` value table: `(application_identifier, key, value)` where `value` is a binary-plist BLOB |
| `key_tab` | `applicationState.db` table mapping the per-device integer key id to its string name (JOIN by name, not number) |
| `compatibilityInfo` | `kvs` key whose BLOB plist embeds an app's bundle- and data-container paths — the consolidated UUID→path map |
| `_UninstallDate` | `kvs` key holding an `NSDate` — proof (with timestamp) that an app was removed even after its container is gone |
| `XBApplicationSnapshotManifest` | `kvs` key inventorying the app-switcher snapshot images (cached last-screen of each backgrounded app) and their on-disk location |
| MobileInstallation logs | `installd`'s rotated text log (`/private/var/installd/Library/Logs/MobileInstallation/mobile_installation.log.N`, iOS 10+) of install/update/uninstall events with timestamps and versions |
| `iTunesMetadata.plist` | Bundle-container plist recording an App Store app's purchasing Apple ID (`AppleID`/`DSPersonID`), version, and download date |
| `MCMMetadataIdentifier` | Key in each container's metadata plist holding the authoritative bundle/group ID — the UUID→bundle answer |
| App Group container | Shared read-write container (`/private/var/mobile/Containers/Shared/AppGroup/<UUID>`) that frequently holds an app's *primary* database |
| iLEAPP | Brignoni's open-source iOS Logs/Events/Plist parser; ingests FFS dumps/backups and produces the installed-apps/container map and per-artifact reports |
| mvt (mvt-ios) | Mobile Verification Toolkit; enumerates apps and runs IOC-driven spyware checks against iOS backups and filesystem dumps |
| AFC (Apple File Conduit) | USB service exposing `/private/var/mobile/Media` (DCIM + `Photos.sqlite`) to a host without a jailbreak |
| Backup domain | The `Manifest.db` re-addressing of an iOS backup — `HomeDomain` / `AppDomain-<bundleid>` / `AppDomainGroup-<groupid>` / `CameraRollDomain` + a `relativePath`, replacing the FFS path tree with `SHA‑1(domain-relativePath)` blobs |

## Further reading

- Apple — *File System Programming Guide* / App Sandbox & App Groups documentation (developer.apple.com); Apple Platform Security guide (Data Protection classes that gate readability).
- Alexis Brignoni — "Identifying installed and uninstalled apps in iOS" + the `applicationState.db` / `kvs` / `key_tab` writeups (abrignoni.blogspot.com); **iLEAPP** (github.com/abrignoni/iLEAPP) installed-apps and applicationState modules.
- Heather Mahalik / Magnet Forensics — "iOS: Tracking Bundle IDs for Containers, Shared Containers, and Plugins" (the canonical metadata-plist → bundle-ID method).
- Yogesh Khatri — "iOS Application Groups & Shared data" (swiftforensics.com); **mac_apt** for batch parsing.
- Ian Whiffin (d204n6) — "iOS: Tracking Traces of Deleted Applications" (blog.d204n6.com) — the uninstall-evidence chain in practice.
- Mattia Epifani / Digital Forensics (zena forensics) — "A first look at iOS 18 forensics" (blog.digital-forensics.it) — the iOS 18 path changes incl. `applicationState.db`.
- *iOS Mobile Installation Logs* — DFIR Review (dfir.pubpub.org) and the MobileInstallation log parser writeups.
- Mobile Verification Toolkit — docs.mvt.re (`mvt-ios check-fs` / `check-backup` / `decrypt-backup`).
- Josh Hickman — public iOS reference images (thebinaryhick.blog / Digital Corpora) for Labs 2–3; RealityNet `iOS-Forensics-References` (github.com) — a curated path-by-path index.
- `man plutil`, `xcrun simctl help`, `sqlite3 .help`, `ileapp.py -h`, `mvt-ios --help`.

---
*Related lessons: [[filesystem-layout-and-containers]] | [[the-itunes-finder-backup-format]] | [[knowledgec-db-deep-dive]] | [[biome-and-segb-streams]] | [[communications-imessage-and-sms]] | [[photos-and-the-camera-roll]] | [[full-file-system-acquisition]] | [[deleted-data-recovery]] | [[the-ios-timestamp-zoo]]*
