---
title: "Filesystem layout & app containers"
part: "02 — System Architecture & Internals"
lesson: 08
est_time: "45 min read + 20 min labs"
prerequisites: [apfs-on-ios-volumes]
tags: [ios, filesystem, containers, layout, forensics]
last_reviewed: 2026-06-26
---

# Filesystem layout & app containers

> **In one sentence:** iOS throws away the browsable, human-named home directory you knew on macOS and replaces it with opaque per-install UUID directories — a read-only **Bundle container** for signed code and a read-write **Data container** for everything the app stores — so the first move in every iOS examination is resolving a UUID back to a bundle ID via the `.com.apple.mobile_container_manager.metadata.plist`, and the rest of the job hangs off the directory map in this lesson.

## Why this matters

Every artifact lesson in Part 08 — Messages, Photos, Safari, location, knowledgeC, Biome — is "go to *this* path and parse *this* file." But on iOS that path begins with a 36-character UUID like `8A3F…D2C1` that means nothing on its own and changes on every reinstall. A parser that doesn't first build the **UUID → bundle-ID map** is reading directories blind. This lesson is the forensic skeleton: the fixed `/private/var` skeleton that never moves, the Bundle/Data/Group split that defines where an app *can* write, and the one metadata plist that turns an opaque GUID directory back into "this is WhatsApp's data container." Get this map wrong and you'll attribute one app's evidence to another; get it right and the whole filesystem becomes legible. It is also the mental model you need as a developer — it's exactly why you can't hardcode a path to your own Documents folder, and why an App Group is the only way two of your processes share a file.

## Concepts

### The shape of the problem: opaque UUIDs instead of a browsable home

On macOS you navigated a *home* — `~/Library/Application Support/com.foo.Bar/`, `~/Library/Containers/com.foo.Bar/Data/`. Directory names *were* identifiers: you could `ls ~/Library/Containers` and read off every sandboxed app by bundle ID. iOS deletes that affordance. App storage lives under directories named by an opaque, randomly generated **UUID** assigned at install time by `installd`/`containermanagerd`, with **no bundle ID in the path**. Worse, each app gets *at least two* unrelated UUIDs — one for its code, one for its data — and the UUIDs are regenerated on every reinstall, so they are meaningful only *within a single filesystem image*.

> 🖥️ **macOS contrast:** macOS App Sandbox containers are named by bundle ID — `~/Library/Containers/com.apple.Notes/Data/`, `~/Library/Group Containers/group.com.apple.notes/` — so the directory tree is self-documenting. iOS uses the same *concept* (a per-app sandbox with Bundle/Data/Group roles) but names every container with an opaque per-install UUID. The translation table you never needed on macOS — UUID → bundle ID — becomes step zero of every iOS exam. macOS's Group Containers are prefixed with the Team ID (`TEAMID.group.com.foo`); iOS App Groups collapse to a bare UUID.

### `/private/var/mobile` — the user home

`/var` is a symlink to `/private/var` (a BSD inheritance, same as macOS). The single interactive user on iOS is `mobile` (uid 501); the user "home directory" is **`/private/var/mobile`**. There is no `/Users`. Everything user-attributable lives under `/private/var/mobile`; system-wide state lives in sibling `/private/var` subtrees (`/private/var/db`, `/private/var/preferences`, `/private/var/Keychains`, `/private/var/wireless`, `/private/var/installd`, `/private/var/containers`, `/private/var/root` for uid 0's home).

A forensically-minded skeleton of the Data volume (mounted at `/` via APFS firmlinks — see [[03-apfs-on-ios-volumes]]):

```
/ (Data volume, /System/Volumes/Data on the SSV split)
├── private/
│   └── var/
│       ├── mobile/                         ← the user home (uid 501)
│       │   ├── Library/                     system-app & framework data (SMS, Mail, Preferences…)
│       │   ├── Media/                       DCIM, Photos, iTunes_Control, recordings (the "AFC" area)
│       │   ├── Containers/
│       │   │   ├── Data/Application/<UUID>/      ← per-app READ-WRITE data containers
│       │   │   └── Shared/AppGroup/<UUID>/       ← App Group shared containers
│       │   └── Applications/                 (legacy pre-iOS 8 flat app dirs — absent on modern images)
│       ├── containers/
│       │   ├── Bundle/Application/<UUID>/        ← per-app READ-ONLY signed code (the .app)
│       │   └── Shared/SystemGroup/<GUID>/        ← system-daemon shared containers
│       ├── Keychains/keychain-2.db          ← the keychain (NOT inside any app container)
│       ├── db/                              system SQLite + the system Biome, lockdown, timezone
│       ├── installd/                        MobileInstallation state, install logs
│       ├── preferences/                     global (com.apple.*) preferences, SystemConfiguration
│       └── wireless/                        baseband / cellular (Library/Databases/CellularUsage.db…)
└── ...
```

Note the deliberate asymmetry that trips up newcomers: **read-write app data sits under `/private/var/mobile/Containers/`**, but **read-only app code sits under `/private/var/containers/`** (no `mobile`). Two different roots. Memorize it.

### The Bundle/Data split — the central concept

iOS splits every installed app into two physically separate, differently-protected containers:

| | **Bundle container** | **Data container** |
|---|---|---|
| Path | `/private/var/containers/Bundle/Application/<UUID>/` | `/private/var/mobile/Containers/Data/Application/<UUID>/` |
| Holds | the signed `.app` (Mach-O, resources, `Info.plist`, `_CodeSignature/`; `embedded.mobileprovision` **only on non-App-Store builds**) | everything the app writes: `Documents/`, `Library/`, `tmp/`, `SystemData/` |
| Writable? | **No** — code-signed, read-only, on a verified mount; writing would break the signature | **Yes** — this is the only place the app may persist data |
| UUID stability | regenerated on **reinstall** (and on app *update* the new `.app` may land in a new bundle UUID) | regenerated on **reinstall**; survives in-place app updates |
| Forensic payload | `iTunesMetadata.plist` (purchaser Apple ID!), `Info.plist`, FairPlay `SC_Info/` | the actual evidence — databases, plists, caches, media |

The two UUIDs are **unrelated random values** — the bundle container UUID is not the data container UUID for the same app. This separation is *the* architectural reason iOS code-signing holds at runtime: code lives on an immutable, verified mount and can never be modified in place, while mutable data is quarantined to a sandbox the kernel's sandbox profile pins to that one app (see [[05-the-sandbox-and-tcc]], [[04-code-signing-amfi-entitlements]]).

```
   App "WhatsApp" (com.whatsapp.WhatsApp) — TWO containers, TWO UUIDs:

   /private/var/containers/Bundle/Application/
        9F2C…A7/                         ← bundle UUID (read-only)
        ├── WhatsApp.app/
        │    ├── WhatsApp           (Mach-O, FairPlay-encrypted — it's an App Store app)
        │    ├── Info.plist
        │    └── _CodeSignature/CodeResources
        │       (no embedded.mobileprovision — App Store strips it; it appears only on
        │        dev / ad-hoc / enterprise / sideloaded builds)
        ├── iTunesMetadata.plist    ← purchaser Apple ID, download date, version
        ├── BundleMetadata.plist
        ├── SC_Info/                ← FairPlay .sinf/.supf keys (App Store apps)
        └── .com.apple.mobile_container_manager.metadata.plist   ← UUID→bundle map

   /private/var/mobile/Containers/Data/Application/
        3B7E…11/                         ← data UUID (read-write) — the evidence
        ├── Documents/              ← user files, often the app's main SQLite DB
        ├── Library/
        │    ├── Preferences/<bundleid>.plist
        │    ├── Caches/
        │    ├── Application Support/
        │    └── Cookies/Cookies.binarycookies
        ├── SystemData/
        ├── tmp/
        └── .com.apple.mobile_container_manager.metadata.plist   ← UUID→bundle map
```

> 🔬 **Forensics note:** `iTunesMetadata.plist` in the bundle container is a high-value attribution artifact. For App Store apps it records the **purchasing Apple ID** (`com.apple.iTunesStore.downloadInfo` → `accountInfo` → `AppleID`/`DSPersonID`), the app version, bundle short version, genre, and the download/purchase date. It can tie an installed app to a specific iCloud account even when the app itself is empty — useful for "whose device is this" and for spotting apps sideloaded under a different account.

### Inside the Data container

The Data container mirrors the macOS app-sandbox `Data/` skeleton, which is why your macOS instincts mostly transfer:

| Subdir | Contents | Forensic relevance |
|---|---|---|
| `Documents/` | user-visible files; for many apps the primary SQLite store | the app's main evidence DB often lives here |
| `Documents/Inbox/` | files opened *into* the app from elsewhere (`UIDocumentInteraction`) | provenance: a file the user received/opened |
| `Library/Preferences/<bundleid>.plist` | `NSUserDefaults` | settings, last-used state, account hints |
| `Library/Caches/` | regenerable caches; survives until space pressure | often retains deleted-from-UI data; *not* backed up |
| `Library/Application Support/` | app-managed persistent data | secondary databases |
| `Library/Cookies/Cookies.binarycookies` | per-app HTTP cookies (binary, not SQLite) | session/auth artifacts |
| `Library/WebKit/`, `Library/Caches/WebKit/` | embedded `WKWebView` state (LocalStorage, IndexedDB) | in-app browser history/data |
| `Library/SplashBoard/` | launch-storyboard snapshots | last-screen imagery on app switch |
| `SystemData/` | system-managed per-app data | |
| `tmp/` | scratch; purged aggressively by the OS | rarely useful, occasionally a deleted-file window |

> 🖥️ **macOS contrast:** This is the *same* `Data/{Documents,Library,tmp}` layout you saw inside `~/Library/Containers/<bundle id>/Data/` for sandboxed Mac apps. iOS made the sandbox **mandatory for every app** (macOS only sandboxes App Store / opted-in apps), and swapped the bundle-ID directory name for a UUID. If you can parse a macOS container you can parse an iOS one — once you've resolved the UUID.

### Inside the Bundle container

The Bundle container is the unpacked, *installed* form of the IPA payload (see [[04-the-app-bundle-and-ipa-structure]]). The `.app` itself is what was code-signed; the kernel's AMFI refuses to execute anything inside it that isn't covered by `_CodeSignature/CodeResources` and the embedded signature. Alongside the `.app`:

- **`iTunesMetadata.plist`** — store/purchase metadata (above).
- **`BundleMetadata.plist`** — install bookkeeping (`MCMMetadata`-adjacent install info).
- **`SC_Info/`** — present for App Store (FairPlay-encrypted) apps: `<App>.sinf` / `.supf` hold the per-device FairPlay key material that decrypts the main Mach-O's encrypted `__TEXT` at load. Decrypting an App Store binary statically is the whole point of [[03-fairplay-encryption-and-decrypting-app-store-apps]]; sideloaded / enterprise / `frida`-injected apps are not FairPlay-wrapped and have no `SC_Info/`.
- **`embedded.mobileprovision`** — the embedded provisioning profile, present **only on non-App-Store builds** (development, ad-hoc, enterprise/in-house, sideloaded). Apple **strips it during App Store ingestion**, so a store-installed app has none. Its presence-or-absence is therefore a distribution-channel tell, paired *inversely* with `SC_Info/`: **App Store ⇒ no profile + `SC_Info/` present; dev / ad-hoc / enterprise / sideloaded ⇒ profile present + no `SC_Info/`.** When present it's a CMS-signed (PKCS#7) plist worth parsing — it carries the signing **Team ID**, the requested **entitlements**, the provisioned device **UDIDs** (ad-hoc/development), and the profile's creation/expiry dates: strong attribution and "how did this app get here" evidence on a sideloaded or enterprise-signed app.
- **`.com.apple.mobile_container_manager.metadata.plist`** — the keystone, below.

### Shared containers — App Groups

An app and its extensions (a Today widget, a Share extension, a keyboard, a Notification Service extension) run as **separate processes with separate Data containers** — they cannot see each other's `Documents/`. The sanctioned channel is an **App Group**: a shared container both processes are entitled to, declared via the `com.apple.security.application-groups` entitlement.

```
/private/var/mobile/Containers/Shared/AppGroup/<UUID>/
        ├── Library/
        ├── <shared SQLite, plists, files>
        └── .com.apple.mobile_container_manager.metadata.plist   ← group-ID, not bundle-ID
```

The group's metadata plist resolves its UUID to a **group identifier** (e.g. `group.com.apple.notes`, `group.net.whatsapp.WhatsApp.shared`), not a bundle ID. This matters forensically because **a lot of the real evidence lives in the App Group, not the app's own Data container.** WhatsApp's message database (`ChatStorage.sqlite`) lives in its App Group; Apple Notes' `NoteStore.sqlite` lives in `group.com.apple.notes`; many apps put their Core Data store in the group so the extension can read it. If you only enumerate `Data/Application/<UUID>` containers you will miss them.

> 🔬 **Forensics note:** When an app's main Data container looks suspiciously empty, check `Shared/AppGroup/`. The mapping from app → its group(s) is in the *app's* metadata plist `MCMMetadataInfo` and, more reliably, in `applicationState.db` / the entitlements embedded in the bundle. iLEAPP and Cellebrite/Magnet resolve groups automatically; doing it by hand means reading each group's metadata plist for its `MCMMetadataIdentifier`.

### System group containers

`/private/var/containers/Shared/SystemGroup/<GUID>/` is the **system daemon** analogue of App Groups — shared containers for Apple's own first-party subsystems (not third-party apps). These hold a surprising amount of high-value system evidence behind opaque UUIDs:

- `systemgroup.com.apple.configurationprofiles` — installed configuration profiles / MDM state (see [[04-configuration-profiles-and-mobileconfig]]).
- `systemgroup.com.apple.mobilewifi` — Wi-Fi known-networks / `com.apple.wifi.known-networks.plist`.
- `systemgroup.com.apple.icloud.findmydeviced.managed` — Find My state.
- `systemgroup.com.apple.nsurlsessiond` — background-download bookkeeping.

Same resolution problem, same fix: read each one's `.com.apple.mobile_container_manager.metadata.plist`.

### The metadata plist — resolving UUID → bundle ID (the keystone)

Every container — Bundle, Data, App Group, System Group — carries a hidden file at its root:

```
.com.apple.mobile_container_manager.metadata.plist
```

It is a small binary plist written and owned by **`containermanagerd`** (whose logic lives in the private `MobileContainerManager.framework` / `ContainerManagerCommon.framework`). It is the authoritative, *local* record of "what is this directory for." Its keys:

| Key | Type | Meaning |
|---|---|---|
| `MCMMetadataIdentifier` | String | **The bundle ID or group ID** this container belongs to (e.g. `com.apple.MobileSMS`, `group.com.apple.notes`). *This is the answer.* |
| `MCMMetadataInfo` | Dict | Nested install metadata: code-info identifier, entitlement-derived data, related identifiers |
| `MCMMetadataContentClass` | Integer | Which *kind* of container this is (app data, app bundle, group, plugin/extension, etc.) — an enum from `MCMMetadata.h`; **verify the exact integer→class mapping against your iOS version before relying on numeric values** |
| `MCMMetadataSchemaVersion` | Integer | Plist schema version (rises across iOS releases) |
| `MCMMetadataUUID` | Data/String | The container's own UUID (matches the directory name) |

So the per-image attribution algorithm is mechanical. The four container roots an examiner must sweep, side by side:

```
ROOT                                                    metadata identifier resolves to
────────────────────────────────────────────────────   ────────────────────────────────
/private/var/containers/Bundle/Application/<UUID>/       a bundle ID  (read-only code)
/private/var/mobile/Containers/Data/Application/<UUID>/  a bundle ID  (read-write data + extensions)
/private/var/mobile/Containers/Shared/AppGroup/<UUID>/   a group ID   (group.*)
/private/var/containers/Shared/SystemGroup/<GUID>/       a system group ID (systemgroup.*)
```

The end-to-end resolution, the way a parser (or you, by hand) walks it:

1. Enumerate every `<UUID>/` directory under each of the four roots.
2. In each, open `.com.apple.mobile_container_manager.metadata.plist`.
3. Read `MCMMetadataIdentifier` → the bundle/group ID; read `MCMMetadataContentClass` → whether it's app-data, an app-bundle, a group, or a plugin/extension.
4. Build a join table: `UUID ↔ identifier ↔ content-class ↔ root`. Group an app's bundle UUID, data UUID, extension UUIDs, and group UUIDs under one identifier stem.
5. *Now* every "go to this app's database" instruction in Part 08 has a concrete path. Every iOS forensic parser does exactly this on ingest.

> 🔬 **Forensics note:** The metadata plist is the *ground truth* and it's local — it survives even when the higher-level install databases are missing or the device is offline. If you can read the filesystem you can rebuild the entire app inventory from these plists alone, with no network and no Apple lookup. Conversely, because the UUID is per-install, **never use a container UUID as a cross-device or cross-acquisition identifier** — correlate on `MCMMetadataIdentifier` (the stable bundle ID), not on the directory name.

### The aggregate maps: applicationState.db & MobileInstallation

Reading thousands of metadata plists is fine for a tool but slow by hand; iOS also keeps consolidated indexes you can query directly:

- **`/private/var/mobile/Library/FrontBoard/applicationState.db`** (SQLite) — SpringBoard/FrontBoard's per-app state. `application_identifier_tab` lists every app's bundle ID; the `kvs` table holds BLOB-plist values (keyed via `key_tab`) including the **sandbox/container path** and `XBApplicationSnapshotManifest` (the app-switcher snapshot inventory). This is the fastest single-file "bundle ID ↔ container path" map, and the snapshot manifest is its own evidence (it tells you which app-switcher screenshots exist and where).
- **`/private/var/installd/Library/MobileInstallation/`** — `installd`'s logs and bookkeeping (`LastBuildInfo.plist`, install/uninstall history in the logs). Older iOS exposed a single `com.apple.mobile.installation.plist`; modern iOS distributes this into `installd` state + per-container metadata plists.

> 🔬 **Forensics note:** `applicationState.db` answers "what apps are/were installed and where is each one's data," and its `XBApplicationSnapshotManifest` corroborates app usage with the cached app-switcher images on disk — a quiet way to recover what an app last displayed even if its own data is locked or wiped.

### Extension & plugin containers — the third UUID you'll miss

App extensions (Share, Today/widget, Notification Service, custom keyboards, Action, File Provider) are **PluginKit plugins** — separate executables with *their own* Data containers, distinct from the host app's. They surface as additional UUID directories under `Data/Application/` (or, on some layouts, a sibling `Data/PluginKitPlugin/` tree), each carrying a metadata plist whose `MCMMetadataIdentifier` is the **plugin's** bundle ID (typically the host's ID plus a suffix, e.g. `com.whatsapp.WhatsApp.ShareExtension`) and a `MCMMetadataContentClass` flagging it as a plugin. The plugin's code lives back inside the *host's* Bundle container at `<App>.app/PlugIns/<Extension>.appex/`.

> 🔬 **Forensics note:** Extensions are a quiet evidence source. A Share/Notification-Service extension can persist data its host never writes — and because it resolves to a *different* bundle ID, a per-app triage that only looks at the host container misses it entirely. When you enumerate the metadata plists, keep the `*.appex`-style identifiers; they tell you which extensions ran and gave them somewhere to leave traces.

### Historical layout — why old images look different

The Bundle/Data split is an **iOS 8** invention. Before iOS 8, every app installed into a single mixed directory at `/private/var/mobile/Applications/<UUID>/`, where the `.app`, `Documents/`, `Library/`, and `tmp/` all lived together under one UUID — code and data in the same writable tree. iOS 8 separated them into the read-only Bundle container and the read-write Data container precisely to keep mutable data off the code-signed mount. You'll still encounter the old `/private/var/mobile/Applications/` layout in legacy images, jailbroken-device archives, and old case material — recognize it so you don't waste time looking for the container split on an image that predates it.

> 🖥️ **macOS contrast:** macOS made the inverse historical move — it *added* an optional sandbox-container layer (`~/Library/Containers/`) on top of a filesystem where unsandboxed apps still scatter data across `~/Library/Application Support`, `~/Library/Preferences`, and `~/Library/Caches` by bare bundle ID. iOS started flat, then enforced the split universally; macOS started open and bolted the sandbox on for App Store apps only. An iOS image therefore has *fewer* places an app can legally write than a Mac — which, for once, makes the examiner's job narrower.

### The key `/private/var/mobile/Library` subdirectories

System apps and frameworks predate the container model and store data in a flat, *named* `~/Library`-style tree under `/private/var/mobile/Library` — this part of iOS still looks like macOS's `~/Library`. The forensic high-value subset (covered in depth in Part 08):

| Path (under `/private/var/mobile/Library/`) | Store | Lesson |
|---|---|---|
| `SMS/sms.db` | iMessage/SMS messages + `Attachments/` | [[04-communications-imessage-and-sms]] |
| `CallHistoryDB/CallHistory.storedata` | call log (Core Data) | [[05-call-history-voicemail-contacts-interactions]] |
| `AddressBook/AddressBook.sqlitedb` | contacts | [[05-call-history-voicemail-contacts-interactions]] |
| `Mail/` | mail accounts, `Envelope Index`, `.emlx` | [[09-mail-notes-calendar-reminders]] |
| `CoreDuet/Knowledge/knowledgeC.db` | legacy pattern-of-life (pre-displacement by Biome) | [[01-knowledgec-db-deep-dive]] |
| `Biome/streams/{public,restricted}/` | SEGB pattern-of-life streams (knowledgeC's successor) | [[02-biome-and-segb-streams]] |
| `Caches/com.apple.routined/` (`Cache.sqlite`) | significant-location / location history | [[07-location-history]] |
| `Preferences/` | global `com.apple.*` preference plists | [[13-notifications-keyboard-and-misc-stores]] |
| `Keyboard/` | learned-word / dynamic-text dictionaries, `lexicon` | [[13-notifications-keyboard-and-misc-stores]] |
| `Recents/com.apple.corerecents.recentsd` | recent-contact interactions, Apple apps (Phone/Messages/Mail) | [[05-call-history-voicemail-contacts-interactions]] |
| `Logs/CrashReporter/` | crash logs (also feeds sysdiagnose) | [[12-unified-logs-sysdiagnose-crash-network]] |
| `Health/healthdb*.sqlite` | HealthKit (often the most sensitive store on the device) | [[10-health-and-fitness]] |

> 🖥️ **macOS contrast:** This `/private/var/mobile/Library/{SMS,Mail,Preferences,Caches,Keyboard,Logs}` tree is the direct descendant of macOS's `~/Library/{Messages,Mail,Preferences,Caches,…}`. The first-party apps kept the old layout; only *third-party* and modern sandboxed first-party apps moved into UUID containers. So an iOS image is a hybrid: a familiar named `~/Library` for the OS, and opaque UUID containers for apps.

### The Media area — `/private/var/mobile/Media`

`/private/var/mobile/Media` is the **AFC-exposed** partition — the only area a non-jailbroken device shares over USB (Apple File Conduit / `house_arrest`) without a backup. It holds:

- `DCIM/` — camera-roll originals (`IMG_xxxx.HEIC/JPG/MOV`), organized in `1xxAPPLE/` buckets.
- `PhotoData/` — the Photos library *database* and derivatives: `PhotoData/Photos.sqlite` (the catalog — see [[06-photos-and-the-camera-roll]]), `PhotoData/Thumbnails/`, `PhotoData/Mutations/`.
- `iTunes_Control/` — media sync bookkeeping.
- `Recordings/` — the **legacy** Voice Memos location; on iOS 12+ Voice Memos records into its own app-group container (`group.com.apple.VoiceMemos`, `Recordings/CloudRecordings.db`), so this folder is often empty/stale on a current image — resolve the group, don't assume Media.
- `Downloads/`, `Books/`, `PublicStaging/`, `MediaAnalysis/`.

> 🔬 **Forensics note:** Because `/private/var/mobile/Media` is the AFC area, it's reachable over USB on an *unlocked* (AFU) device with no jailbreak — `afcclient`/`ifuse`/`pymobiledevice3 afc` pull `DCIM/` and `PhotoData/Photos.sqlite` directly. That makes camera-roll + Photos.sqlite one of the cheapest high-value pulls in [[04-logical-acquisition-with-libimobiledevice]]. App containers under `/private/var/mobile/Containers/` are *not* in AFC's view — they require a backup, a `house_arrest` per-app pull (Documents-sharing apps only), or a full-filesystem extraction.

### Where the keychain lives — and where it doesn't

`/private/var/Keychains/keychain-2.db` (SQLite) is the **device keychain**, and note the path: it is under `/private/var/Keychains`, *not* `/private/var/mobile` and *not* inside any app container. Companions *in that directory* are the certificate/trust caches (`TrustStore.sqlite3`, `ocspcache.sqlite3`, `caissuercache.sqlite3`) — **not** the keybags. The Data-Protection **keybags** (`*.kb`, e.g. `systembag.kb`) that hold the wrapped class keys live in a *sibling* tree at **`/private/var/keybags/`** — a path forensic newcomers routinely conflate with `/private/var/Keychains/` (see [[02-data-protection-and-keybags]], [[08-keychain-on-ios]]). Each keychain item is encrypted under a Data-Protection class key, so the rows enumerate without the device key but the secrets do **not** decrypt without on-device key material — which is exactly why keychain decryption is a separate, agent-/exploit-dependent step rather than a file copy.

> 🖥️ **macOS contrast:** macOS carries both the legacy per-user `~/Library/Keychains/login.keychain-db` and the iOS-style per-user data-protection keychain at `~/Library/Keychains/<UUID>/keychain-2.db` (same `keychain-2.db` filename as iOS), plus the system `/Library/Keychains/System.keychain`. iOS consolidates to one system-level `/private/var/Keychains/keychain-2.db`, with per-item Data-Protection classes standing in for macOS's per-keychain unlock model.

### Uninstall leaves traces the container deletion doesn't

Deleting an app tears down its Bundle, Data, and (if no other app uses them) Group containers — the UUID directories vanish and their contents are gone from the live filesystem. But the *fact of installation* persists elsewhere: `installd`'s MobileInstallation logs record installs and removals; the system Biome/knowledgeC `/app/install` and app-usage streams retain the bundle ID and timestamps; `applicationState.db` and SpringBoard icon-layout state (`com.apple.springboard` / `IconState.plist`) can still name a since-removed app; and Apple-account purchase history (the App Store) and any prior backup retain it. So "the container is gone" is *not* "the app was never there."

> 🔬 **Forensics note:** When the question is "did app X ever run on this device," the absence of a container is weak evidence on its own. Pivot to the pattern-of-life stores ([[02-biome-and-segb-streams]], [[01-knowledgec-db-deep-dive]]), the install logs, the icon-state plists, the notification stores, and the device's backups — all of which can name an app whose container has been deleted. A container present *plus* corroborating usage in Biome is the strong case; a missing container is merely "not currently installed."

### The Data-Protection / lock-state caveat on the whole map

Everything above describes *structure*. Whether you can read a given file's *contents* depends on its Data-Protection class and the device's lock state (BFU vs AFU — see [[03-passcode-bfu-afu-and-inactivity]], [[02-bfu-vs-afu-and-data-protection-classes]]). The container *layout* — directory names, the metadata plists, `applicationState.db` — is mostly low-protection metadata you can enumerate even when most file *contents* are still encrypted.

| What you're touching | Typical protection | Available in BFU? |
|---|---|---|
| Container directory names / structure | filesystem metadata | usually yes |
| `.com.apple.mobile_container_manager.metadata.plist` | low (Class D / `NSFileProtectionNone`-adjacent) | usually yes |
| Most third-party app databases (`sms.db`, app SQLite) | Class C (`CompleteUntilFirstUserAuthentication`) or higher | **no** until first unlock (AFU+) |
| Mail, some messaging contents | often Class A/B (`Complete`/`CompleteUnlessOpen`) | no |
| Keychain secrets in `keychain-2.db` | per-item class, device-key wrapped | no (needs on-device key material) |

So you can frequently rebuild the full app inventory and container map of a **BFU** device whose actual evidence files remain locked — but don't confuse "I can list the containers" with "I can read the data." (The exact class assigned to a given file is the app developer's choice via `NSFileProtection*`; treat the table as the common case, not a guarantee.)

## Hands-on

There is no on-device shell. The Simulator stores the *same* container layout **unencrypted on the Mac**, which makes it the perfect place to practice the resolution workflow; device-side commands run from the Mac over `usbmuxd` via libimobiledevice / `pymobiledevice3`.

### Map the container layout in the Simulator

The Simulator mirrors the device layout (minus encryption, SEP, and the `/private` prefix) at
`~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/`.

```bash
# Pick a booted simulator
xcrun simctl list devices booted

# The single cleanest UUID→bundle map: list every installed app with BOTH container paths
xcrun simctl listapps booted | plutil -p - | head -60
#   "com.apple.mobilesafari" => {
#       "Bundle"        => "file:///.../data/Containers/Bundle/Application/9F2C…/MobileSafari.app/"
#       "DataContainer" => "file:///.../data/Containers/Data/Application/3B7E…/"
#       "GroupContainers" => { "group.com.apple.…" => "file:///.../Shared/AppGroup/…/" }
#       "CFBundleIdentifier" => "com.apple.mobilesafari"
#   }

# Resolve a single bundle ID straight to its data / bundle / group container:
xcrun simctl get_app_container booted com.apple.mobilesafari data
xcrun simctl get_app_container booted com.apple.mobilesafari app
xcrun simctl get_app_container booted com.apple.mobilesafari groups
```

### Read a metadata plist by hand (the device-truth method)

```bash
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
CTN=~/Library/Developer/CoreSimulator/Devices/$DEV/data/Containers

# For every Data container, print its UUID directory and the bundle it belongs to:
for d in "$CTN"/Data/Application/*/; do
  id=$(plutil -extract MCMMetadataIdentifier raw \
        "$d/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null)
  printf '%s\t%s\n' "$(basename "$d")" "$id"
done
#   3B7E…11   com.apple.mobilesafari
#   7C19…A4   com.apple.MobileSMS
#   …

# Inspect the full metadata plist for one container:
plutil -p "$CTN"/Data/Application/3B7E…/.com.apple.mobile_container_manager.metadata.plist
```

A real metadata plist (here, a MobileSMS data container) pretty-prints roughly like this — the shape to recognize on sight:

```
{
  "MCMMetadataContentClass" => 2
  "MCMMetadataIdentifier"   => "com.apple.MobileSMS"
  "MCMMetadataInfo" => {
    "ContentDataVersion" => 1
    "Entitlements"       => { … bundle-derived entitlement hints … }
    "Identifier"         => "com.apple.MobileSMS"
  }
  "MCMMetadataSchemaVersion" => 4
  "MCMMetadataUUID" => "7C19…A4"
}
```

`plutil -extract … raw` is the headless way to pull a single key; `plutil -p` pretty-prints the whole thing (binary plists are not greppable as text — always convert first). The two facts you act on are `MCMMetadataIdentifier` (which app) and that `MCMMetadataUUID` matches the directory name (a sanity check that the plist belongs to *this* container and wasn't copied in from elsewhere).

### Device-side: enumerate installs without a jailbreak (walkthrough)

```bash
# Installed-app inventory + bundle paths over USB (no jailbreak):
ideviceinstaller list --all              # bundle IDs, names, versions (older syntax: -l -o list_all)
pymobiledevice3 apps list                 # JSON incl. Path/Container hints

# Reach ONE app's Documents over house_arrest — only apps with UIFileSharingEnabled / Documents-
# sharing. `apps pull` takes <bundle_id> <remote_file> <local_file>; --documents scopes to Documents:
pymobiledevice3 apps pull com.some.app Documents/Store.sqlite ./Store.sqlite --documents
pymobiledevice3 apps afc  com.some.app --documents  # interactive AFC shell (then `pull . ./out`)

# The AFC media area (camera roll + Photos.sqlite) — unlocked device, still no jailbreak:
pymobiledevice3 afc pull /DCIM ./dcim_out
pymobiledevice3 afc pull /PhotoData/Photos.sqlite ./Photos.sqlite
```

> ⚠️ **ADVANCED:** Seeing the *full* `/private/var/mobile/Containers/Data/Application/<UUID>/` tree on a real device requires a **full-filesystem extraction** — a jailbreak (`palera1n` on A8–A11 / checkm8), a known-vulnerability agent (GrayKey/Cellebrite/Elcomsoft), or a `developer-mode` agent — none of which apply to a device you do not lawfully control. Logical/AFC and `house_arrest` only reach the Media area and Documents-sharing apps' `Documents/`. Do not attempt jailbreak steps outside an authorized lab on a device you own. See [[05-full-file-system-acquisition]].

## 🧪 Labs

### Lab 1 — Build the UUID→bundle map (Substrate: iOS Simulator)

**Substrate & fidelity:** CoreSimulator on your Mac. The container *layout and metadata plists are byte-faithful to a device*; what's missing is encryption/Data-Protection, SEP, and the lock-state gating — so this teaches *structure and resolution*, not decryptability.

1. Boot a simulator, install an app (Xcode → run any app, or `xcrun simctl install booted <App.app>`), and add a note/photo so a Data container exists.
2. Run `xcrun simctl listapps booted | plutil -p -`. For one third-party app, record its `Bundle` and `DataContainer` UUIDs — confirm they differ.
3. Now *forget the tool* and rebuild the map by hand with the metadata-plist loop from Hands-on. Confirm your hand-resolved `MCMMetadataIdentifier` matches `simctl`'s `CFBundleIdentifier`. You just did, manually, what every iOS parser does on ingest.

### Lab 2 — Anatomy of one app's two containers (Substrate: iOS Simulator)

**Substrate & fidelity:** as Lab 1.

1. `cd` into one app's Data container (`xcrun simctl get_app_container booted <id> data`). Enumerate `Documents/ Library/ tmp/ SystemData/`. Find `Library/Preferences/<id>.plist` and `plutil -p` it.
2. `cd` into the matching Bundle container (`… get_app_container booted <id> app` then up one level). Locate the `.app`, `_CodeSignature/CodeResources`, and (if present) `iTunesMetadata.plist`. Note: Simulator apps are **not** FairPlay-wrapped, so there's no `SC_Info/` — flag that as a Simulator-vs-device gap.
3. List the app's `groups` and, if any, open the App Group's metadata plist — confirm `MCMMetadataIdentifier` is a `group.*` ID, not the bundle ID.

### Lab 3 — Resolve containers on a real image (Substrate: public sample forensic image, read-only)

**Substrate & fidelity:** a full-filesystem reference image (e.g. Josh Hickman's iOS image from thebinaryhick.blog / Digital Corpora). This is a *real device* layout with the device-only daemons (`routined`, Biome, knowledgeC) populated — the thing the Simulator can't give you. Work on a copy; `cp` any SQLite before `sqlite3`.

1. Navigate to `private/var/mobile/Containers/Data/Application/`. Pick three UUID directories and resolve each via its `.com.apple.mobile_container_manager.metadata.plist` (`plutil -p`). Build a three-row UUID→bundle table.
2. Find an app whose real data lives in an **App Group**, not its Data container (Notes is a reliable example): confirm the Data container is thin and the `Shared/AppGroup/<UUID>` with `MCMMetadataIdentifier = group.com.apple.notes` holds `NoteStore.sqlite`.
3. Locate `private/var/Keychains/keychain-2.db` and `private/var/mobile/Library/FrontBoard/applicationState.db`. Open `applicationState.db` (`cp` first) and confirm `application_identifier_tab` lists the same bundle IDs you resolved by hand in step 1.
4. (Optional) Run **iLEAPP** against the image (`ileapp.py -t fs -i <extracted_root> -o out`) and confirm its "Installed Applications" / container map matches your manual resolution.

### Lab 4 — What a no-jailbreak pull can and can't reach (Substrate: read-only walkthrough + Simulator stand-in)

**Substrate & fidelity:** narration of the device path + a Simulator stand-in for the reachable parts. No device required.

1. On paper, classify each target by reachability without a jailbreak: `DCIM/` (AFC ✅), `PhotoData/Photos.sqlite` (AFC ✅, unlocked), a Documents-sharing app's `Documents/` (`house_arrest` ✅), an arbitrary app's `Library/` (❌ — needs FFS), `keychain-2.db` (❌ — needs FFS + decryption agent).
2. In the Simulator, prove the *reachable* skills: pull a `Photos.sqlite` and a Documents folder, then `sqlite3` the copy. The query/parsing skill is identical to the device case; only the acquisition gate differs.

## Pitfalls & gotchas

- **The two container roots have different parents.** Read-write data is `/private/var/mobile/Containers/…`; read-only code is `/private/var/containers/…` (no `mobile`). Mixing them up sends you to the wrong tree.
- **UUIDs are per-install and per-role.** The bundle UUID ≠ the data UUID for the same app, and *both* change on reinstall. Never key your analysis or your cross-device correlation on a UUID — key on `MCMMetadataIdentifier`.
- **The real evidence is often in the App Group, not the Data container.** WhatsApp's `ChatStorage.sqlite`, Apple Notes' `NoteStore.sqlite`, and many Core Data stores live under `Shared/AppGroup/<UUID>`. Enumerate group containers too, or you'll declare an app "empty."
- **Binary plists are not text.** `grep` on a metadata plist returns nothing useful. Always `plutil -p` / `plutil -convert xml1` / `plutil -extract … raw` first.
- **`Caches/` is not in the backup, and that's why it matters.** Caches are excluded from iTunes/Finder backups but *are* in a full-filesystem extraction — they frequently retain data that has been "deleted" from the UI and from the backed-up databases.
- **Copy SQLite before you query.** Even a `SELECT` on `sms.db`/`Photos.sqlite`/`applicationState.db` takes a write lock and spawns `-wal`/`-shm` sidecars; on an evidence image that alters the artifact. `cp` first, always.
- **`MCMMetadataContentClass` integers drift.** The class enum is defined in `MCMMetadata.h` and its numeric values have changed across iOS releases — read the *string* `MCMMetadataIdentifier` for attribution; treat the content-class integer as advisory and verify against the OS version if you depend on it.
- **Listing ≠ decrypting.** On a BFU/locked device you can often enumerate the whole container map (low-protection metadata) while the file contents stay encrypted. The layout being legible says nothing about whether the evidence is readable.
- **`/var` is a symlink to `/private/var`.** Tools and reports vary in which form they print; they're the same path. Normalize before you diff two evidence inventories or you'll get phantom "differences."
- **First-party apps are a hybrid.** Some Apple apps live in the named `/private/var/mobile/Library` tree (Messages, Mail, Phone), others moved into UUID containers like third-party apps (newer system apps). Don't assume "Apple app ⇒ named path" or "UUID container ⇒ third-party." Resolve, don't guess.
- **An empty or missing container is not proof of absence.** Uninstall removes the container but leaves install/usage traces in Biome, install logs, icon-state, and backups. Conversely a stale container from a since-deleted app can linger in old backups. Date your inventory to the acquisition, not to "now."
- **Simulator gaps.** No FairPlay (`SC_Info/` absent), no SEP/Data-Protection, and the device-only daemons (`knowledged`, `biomed`, `routined`, `powerlogHelperd`) don't populate their device stores — so the Simulator teaches *layout and resolution*, never lock-state or pattern-of-life. Use a sample image for those.

## Key takeaways

- iOS replaces macOS's browsable, bundle-ID-named home with **opaque per-install UUID containers**; resolving UUID → bundle ID is step zero of every iOS exam.
- Every app has **two unrelated containers**: a read-only **Bundle** container (`/private/var/containers/Bundle/Application/<UUID>`) for signed code and a read-write **Data** container (`/private/var/mobile/Containers/Data/Application/<UUID>`) for everything it stores.
- The keystone artifact is **`.com.apple.mobile_container_manager.metadata.plist`** at each container's root; its `MCMMetadataIdentifier` key is the authoritative, offline, local bundle/group ID for that directory.
- **App Groups** (`Shared/AppGroup/<UUID>`) and **System Groups** (`/private/var/containers/Shared/SystemGroup/<GUID>`) are shared containers — and the *real* evidence (WhatsApp/Notes databases, Wi-Fi/profile state) frequently lives there, not in the app's own Data container.
- `/private/var/mobile/Library` keeps the **named, macOS-style `~/Library` tree** for first-party stores (SMS, Mail, Preferences, knowledgeC, Biome, Health); `/private/var/mobile/Media` is the **AFC area** (DCIM + `PhotoData/Photos.sqlite`) reachable over USB without a jailbreak.
- The keychain is **`/private/var/Keychains/keychain-2.db`** — outside every app container; rows enumerate but secrets need on-device key material.
- `applicationState.db` and `installd`'s MobileInstallation state are the **consolidated indexes** that corroborate (and speed up) the per-container metadata-plist resolution.
- **Layout is enumerable even when contents are encrypted** — distinguish "I mapped the containers" (often possible BFU) from "I read the evidence" (gated by Data-Protection class + lock state).

## Terms introduced

| Term | Definition |
|---|---|
| Bundle container | Read-only per-app directory at `/private/var/containers/Bundle/Application/<UUID>` holding the signed `.app` and install metadata |
| Data container | Read-write per-app directory at `/private/var/mobile/Containers/Data/Application/<UUID>` holding `Documents/Library/tmp/SystemData` |
| App Group container | Shared read-write container (`/private/var/mobile/Containers/Shared/AppGroup/<UUID>`) for an app and its extensions, gated by the `application-groups` entitlement |
| System Group container | First-party-daemon shared container at `/private/var/containers/Shared/SystemGroup/<GUID>` |
| `.com.apple.mobile_container_manager.metadata.plist` | Per-container binary plist (managed by `containermanagerd`) recording which bundle/group the UUID directory belongs to |
| `MCMMetadataIdentifier` | The plist key holding the authoritative bundle ID or group ID for a container — the UUID→bundle answer |
| `MCMMetadataContentClass` | Integer enum (from `MCMMetadata.h`) classifying the container kind; numeric values drift across iOS versions |
| `containermanagerd` | The daemon (private `MobileContainerManager`/`ContainerManagerCommon.framework`) that creates and writes container metadata |
| `iTunesMetadata.plist` | Bundle-container plist recording the App Store purchaser Apple ID, version, and download date |
| `SC_Info/` | Bundle-container directory holding FairPlay `.sinf`/`.supf` key material for App Store apps |
| `applicationState.db` | FrontBoard SQLite at `/private/var/mobile/Library/FrontBoard/` mapping bundle IDs to container paths + the app-switcher snapshot manifest |
| AFC (Apple File Conduit) | The USB service that exposes `/private/var/mobile/Media` to a host without a jailbreak |
| `house_arrest` | The per-app AFC service that exposes a single Documents-sharing app's `Documents/` over USB |
| PluginKit plugin (`.appex`) | An app extension — a separate executable inside `<App>.app/PlugIns/` with its own Data container and its own bundle ID |
| keychain-2.db | The device keychain SQLite at `/private/var/Keychains/`, outside any app container, per-item Data-Protection encrypted |

## Further reading

- Apple — *File System Programming Guide* / *File System Basics* (the `Bundle`/`Data`/`tmp` container model) and the App Sandbox / App Groups documentation (developer.apple.com).
- Heather Mahalik / Smarter Forensics & Magnet Forensics — "iOS: Tracking Bundle IDs for Containers, Shared Containers, and Plugins" (the canonical metadata-plist → bundle-ID writeup).
- d204n6 (Ian Whiffin) — container/Biome and `applicationState.db` deep dives (blog.d204n6.com).
- nsantoine.dev — *A Worm's Look Inside: Apple's Sandboxing on macOS & iOS* (container manager + sandbox internals); xybp888/iOS-Header (`MCMMetadata.h` headers).
- Alexis Brignoni — **iLEAPP** (github.com/abrignoni/iLEAPP): see its installed-apps / container-resolution modules for the production version of Labs 1–3.
- Jonathan Levin — *MacOS and iOS Internals, Vol. I* (filesystem & `containermanagerd`); newosxbook.com.
- Elcomsoft / Passware blogs — keychain + full-filesystem extraction context for `/private/var/Keychains/keychain-2.db`.
- Josh Hickman — public iOS reference images (thebinaryhick.blog / Digital Corpora) for Lab 3.
- `man plutil`, `xcrun simctl help`, `pymobiledevice3 --help`, `ideviceinstaller --help`.

---
*Related lessons: [[03-apfs-on-ios-volumes]] | [[00-app-sandbox-and-filesystem-layout]] | [[05-the-sandbox-and-tcc]] | [[04-the-app-bundle-and-ipa-structure]] | [[04-logical-acquisition-with-libimobiledevice]] | [[05-full-file-system-acquisition]] | [[08-keychain-on-ios]]*
