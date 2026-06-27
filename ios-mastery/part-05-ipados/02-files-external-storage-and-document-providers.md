---
title: "Files, external storage & document providers"
part: "05 — iPadOS as a Computer"
lesson: 02
est_time: "45 min read + 20 min labs"
prerequisites: [how-ipados-diverges-from-ios, app-sandbox-and-filesystem-layout]
tags: [ios, ipados, files, file-provider, external-storage, forensics]
last_reviewed: 2026-06-26
---

# Files, external storage & document providers

> **In one sentence:** The Files app looks like Finder but is nothing like it — it is a *brokered, federated viewer* that stitches together independently-sandboxed File Provider extensions, an out-of-process document picker, a small local "On My iPad" container, and on-demand external/SMB mounts, and each of those layers leaves its own distinct artifact trail that an iPhone exam rarely touches but an iPad exam must.

## Why this matters

When the learner thinks "file manager," the Mac model fires: one `Finder` process with read access to the entire user volume, walking a single POSIX tree. **None of that is true on iPadOS.** Files (`com.apple.DocumentsApp`) cannot see the filesystem. It is a *picker and a presenter* that asks the system to enumerate locations on its behalf, and the apps that own those locations stay fully sandboxed the whole time. Understanding *which process actually holds the bytes*, *where they are cached*, and *what a "file" even is when it is dataless tells you, as a forensic examiner, where the evidence lives — and as a builder, why your code gets a security-scoped URL instead of a path. The iPad is the device where users do real document work: download a PDF to a USB-C SSD, edit it from an SMB share, sync it through a third-party cloud provider. Every one of those actions is a document-handling event with on-disk residue, and almost none of it shows up where a macOS reflex would look.

This lesson maps the layer end to end: the broker (`fileproviderd`), the provider contracts, the dataless/materialization lifecycle that decides what bytes are even *on* the device, the sandbox-respecting picker that lets apps touch files without roaming, the local "On My iPad" container, iCloud Drive, and external USB-C/SMB storage — and, for each, exactly where the artifacts live and how to read them without contaminating them.

## Concepts

### Files is a broker, not a filesystem

On macOS, Finder *is* a privileged client of the kernel VFS: it `readdir()`s your home folder directly. On iPadOS there is no such privilege. The Files app is a thin UI over a **federation of providers**, each a separate code module with its own sandbox, reached through the **File Provider** framework and coordinated by the **`fileproviderd`** system daemon.

```
            ┌──────────────────────────────────────────────┐
            │  Files.app  (com.apple.DocumentsApp)          │
            │  — UI only; owns no user files                │
            └───────────────┬──────────────────────────────┘
                            │ NSFileProvider* IPC (XPC)
                  ┌─────────▼─────────┐
                  │   fileproviderd   │  system broker daemon
                  │  (domain registry,│  enumerates, materializes,
                  │   working store)  │  bridges sandboxes
                  └───┬─────┬─────┬───┘
        ┌─────────────┘     │     └─────────────┐
        ▼                   ▼                    ▼
 ┌─────────────┐   ┌──────────────────┐  ┌───────────────────┐
 │ iCloud Drive│   │ Third-party       │  │ "On My iPad" /     │
 │ (bird /     │   │ provider extension│  │ external USB-C /   │
 │  CloudDocs) │   │ (Dropbox, Box,    │  │ SMB share          │
 │             │   │  Synology, …)     │  │ (system providers) │
 └─────────────┘   └──────────────────┘  └───────────────────┘
   each = one or more NSFileProviderDomain  → one Location in the sidebar
```

Each **Location** in the Files sidebar — iCloud Drive, On My iPad, Dropbox, a plugged-in SSD, an SMB server — is backed by one or more `NSFileProviderDomain`s. The crucial property: **the providers never share an address space and never share a sandbox**. Files asks `fileproviderd`; `fileproviderd` asks the right extension; the extension hands back metadata and, on demand, bytes. The user *perceives* one unified tree. The system *implements* a mesh of mutually-isolated sandboxes with a daemon in the middle.

> 🖥️ **macOS contrast:** macOS has the *same* File Provider framework (it is what powers third-party cloud providers in Finder's sidebar and replaced the old "kext-mounted network drive" model), but on macOS it sits *alongside* a fully open POSIX filesystem you can still `cd` into. On iPadOS the File Provider mesh is the *only* file model there is — there is no underlying open tree for the user (or an app) to fall back to. "On My iPad" is the closest thing to a user-visible local folder, and even it is just another provider domain.

### File Provider extensions: replicated vs. non-replicated

A provider is an **app extension** that adopts one of two contracts:

| Model | Principal class | Mental model | Who holds the bytes |
|---|---|---|---|
| **Non-replicated** (legacy) | `NSFileProviderExtension` | "I expose a flat working directory the system manages" | The shared **`File Provider Storage`** folder in an app-group container |
| **Replicated** (modern, iOS 16+/macOS 11+) | `NSFileProviderReplicatedExtension` | "I am the source of truth; the system mirrors my namespace and caches what it needs" | **`fileproviderd`**'s system-managed working store; the extension only describes items |

The modern **replicated** model is the one most current cloud providers ship. The extension never writes files into a folder Files can see; instead it vends an **item tree** — each node an `NSFileProviderItem` (an identifier, parent identifier, filename, content type, size, timestamps, and a set of `NSFileProviderItemCapabilities`). `fileproviderd` reconciles that description against its own on-disk mirror. This is why a third-party provider can show you a 4 TB namespace on a 256 GB iPad: **the tree is metadata; the bytes are fetched lazily.**

### Materialization and dataless files

The single most important concept for both building and examining this layer:

> A file in Files may be **dataless** — present as a fully-described item (name, size, dates, icon) with **no content bytes on the device at all.**

When the user (or any app via `NSFileCoordinator` / `UIDocument`) opens a dataless item, the system **materializes** it: it calls the provider's `fetchContents` (replicated) or `startProvidingItem(at:)` (non-replicated), the provider downloads the bytes, and *only then* does the file exist locally. Conversely, under storage pressure or an explicit "Remove Download," the system **evicts** the content, returning the item to dataless and (for iCloud Drive) leaving a placeholder behind.

```
  dataless item ──open()──▶ fileproviderd ──fetchContents──▶ provider downloads
       ▲                                                          │
       └──────────────── eviction (storage pressure) ◀───────────┘ materialized
```

**Forensically this is decisive:** the *list* of files a user could see is not the same as the *files whose bytes are actually on the device*. A logical or even full-filesystem acquisition captures only what was **materialized at acquisition time** plus placeholders for the rest. The presence of a placeholder proves the file *existed in the namespace*; only a materialized copy proves the *content* was ever on the device.

> 🖥️ **macOS contrast:** This is exactly the macOS "dataless file" you already know — the `SF_DATALESS` flag you can see with `ls -lO` / `find . -flags dataless`, and the `com.apple.fileprovider.fpfs#P` / `brctl` machinery. Same framework, same eviction logic, same placeholder concept. On macOS you can watch a file go dataless and back; on iPadOS the mechanism is hidden behind the cloud/download chevrons in the Files UI, but the on-disk semantics are identical.

> 🔬 **Forensics note:** Never report "the device contained file X" from a Files listing alone. Distinguish **enumerated** (the item was in a provider's namespace) from **materialized** (content bytes were on the device). For iCloud Drive, an evicted file is replaced by a hidden placeholder named `.<originalname>.<ext>.icloud` — a small binary plist recording the original filename and logical size but **no content**. Decoding that placeholder tells you a file existed and its size, not what was in it.

### Capabilities, the working set, and conflict handling

Each `NSFileProviderItem` advertises an **`NSFileProviderItemCapabilities`** bitmask — `.allowsReading`, `.allowsWriting`, `.allowsRenaming`, `.allowsReparenting` (move), `.allowsTrashing`, `.allowsDeleting`, `.allowsEvicting`. This is what greys out actions in the Files UI: a read-only SMB share or a permission-limited cloud folder reports reduced capabilities, and the system refuses the operation *before* it ever reaches the provider. For an examiner, capabilities recorded in a provider's cached metadata can show whether a user *could* have modified a file at all.

Two more concepts shape what persists on disk:

- **The working set** — the system keeps an always-materialized *metadata* set (the items reachable through Recents, Favorites, Tagged, and recently-used) so those views render instantly even offline. The provider feeds it via an `NSFileProviderEnumerator` over the `.workingSet` container and bumps an **anchor** as the namespace changes. The working-set metadata can outlive the content and is a place "recently touched" items leave a trace even after eviction.
- **Conflict handling** — File Provider is offline-first. A local edit made while disconnected is reconciled on reconnect; an unresolvable clash produces a **conflict copy** (the provider creates a second item, often a "(conflicted copy)"-style name). Those copies are real files on disk and frequently capture content a user *thought* was overwritten.

> 🔬 **Forensics note:** Conflict copies and working-set residue are quiet evidence: a "conflicted copy" preserves a divergent version of a document, and working-set metadata can name files no longer materialized. Both survive ordinary user cleanup because the user never sees them as separate things in the UI.

### Spotlight indexing of Files content

Files content is searchable because providers donate items to **Core Spotlight** (`CSSearchableItem` / the on-device search index) — that is how Files search returns hits inside documents and across providers. The index lives in the device's Spotlight stores (the `CoreSpotlight`/`spotlightknowledge` data), separate from the providers themselves, and can retain **titles, snippets, and metadata for items that are now dataless or deleted**. It is the iPad analogue of the macOS `.Spotlight-V100` angle for "files that existed."

> 🔬 **Forensics note:** When a document's bytes are gone (evicted or deleted), the Spotlight/Core Spotlight index may still hold its name and a content snippet donated when it was last indexed — sometimes enough to establish *what* a missing file contained. Flag the exact iOS 26 Core Spotlight store paths to verify against your acquisition rather than assuming a fixed location.

### Third-party providers and the BASE64 account namespace

A third-party cloud app (Dropbox, Box, Google Drive, Synology Drive, Nextcloud/ownCloud, …) becomes a Location by shipping a File Provider extension and calling **`NSFileProviderManager.add(_:completionHandler:)`** to register one domain per signed-in account. The extension declares the right `NSExtensionPointIdentifier` in its `Info.plist` — historically `com.apple.fileprovider-nonui` (the silent provider) and `com.apple.fileprovider-actionsui` (the optional custom-action UI). Once registered, the provider is just another node in the mesh: enumerate = metadata, open = materialize.

Forensically, the bytes split across **two** containers worth checking:

```
group.com.apple.FileProvider.LocalStorage/File Provider Storage/
        <BASE64-encoded account/domain id>/   ← per-account subtree (legacy non-replicated)
                <files cached locally, original names under the encoded root>
.../Containers/Data/Application/<app-uuid>/            ← the provider app's OWN sandbox
        Documents/ , Library/ , <Provider>.sqlite      ← the app's private offline cache/index
```

The per-account folder names under `File Provider Storage` are **BASE64-encoded** — decode them to recover the account identifier. Each provider app *also* keeps a private database in its own container (e.g. a `Dropbox.sqlite`-style index of offline/starred files) that an examiner should parse separately, because it can list files the user marked for offline use, and timestamps, that the system-level working store does not.

> 🔬 **Forensics note:** Treat a third-party provider as two artifacts in one: (1) the **system working store** (`File Provider Storage/<base64>/`) holding what the OS materialized, and (2) the **app's own container** holding the provider's private sync database. The two can disagree — the app DB may name files that were never materialized, and the working store may hold evicted-then-refetched copies the app DB no longer tracks. Decode the BASE64 folder name to attribute the cache to a specific account.

### The document picker: how a sandboxed app reaches a file it doesn't own

A third-party app cannot enumerate Files. When it needs to import or export a document it presents **`UIDocumentPickerViewController`**, which is **not in-process** — the picker UI, the enumeration, and the file selection all run in a separate system process (the document-management service) the calling app can neither see into nor control. Control crosses a process boundary the app cannot follow:

```
 app (sandboxed)            system picker process            provider
 ───────────────            ─────────────────────            ────────
 present picker  ───────▶   user browses Locations  ──────▶  enumerate
                            user taps file
 security-scoped URL ◀───────────────────────────────────   (materialize)
 startAccessing…()
   read/write within grant
 stopAccessing…()
 (persist bookmark for next launch)
```

The app receives only the chosen URL with a scoped grant — it never gains the ability to *list* a Location. This is the architectural reason a malicious app cannot use the picker to exfiltrate a directory: it gets exactly the file the human tapped, nothing adjacent. It must then bracket every access:

```swift
let didStart = url.startAccessingSecurityScopedResource()
defer { if didStart { url.stopAccessingSecurityScopedResource() } }
// read/write the file here, inside the grant
```

For persistent access across launches the app serializes a **security-scoped bookmark** with `url.bookmarkData()` (on **macOS** this needs the explicit `.withSecurityScope` option; on **iOS/iPadOS** a document-picker URL is already security-scoped, so no special option is required) and resolves it on next launch with `URL(resolvingBookmarkData:bookmarkDataIsStale:)`.

**Open-in-place vs. import — two outcomes that leave different traces.** The picker's `asCopy` flag (modern `UIDocumentPickerViewController(forOpeningContentTypes:asCopy:)`) decides which path a document takes. **Open-in-place** (`asCopy: false`, and the app declares `LSSupportsOpeningDocumentsInPlace = YES`) hands back a URL pointing at the *original* item in its provider — edits write back through the provider, so there may be **no copy in the app's container at all**, and the evidence of the edit lives in the provider/working store. **Import/copy mode** (`asCopy: true`) duplicates the file *into* the app's own container, creating a second, now-independent copy that diverges from the original. For an examiner: a document edited in place updates the source (and the provider's sync/upload records), while an imported copy produces a forked artifact in the editing app's sandbox — checking only one side misses half the story. This is the sandbox reconciliation: **Files is a system-mediated picker, not a capability to roam.** The user's *tap* is the consent event that mints a narrow, per-file grant; the app still cannot list, glob, or walk anything it wasn't handed. Apps that want to *be* a file browser embed **`UIDocumentBrowserViewController`** (a full Files-like browser the system hosts on their behalf) rather than getting raw access.

One historical note worth carrying: the modern File Provider framework **subsumed** the iOS 8-era **"Document Provider"** extension model — the old document-picker extension pairing (a non-UI provider + a `Document Picker` UI extension) is the ancestor of today's `com.apple.fileprovider-nonui` / `com.apple.fileprovider-actionsui` extension points, and the *export-to-other-app* path that used to be "Open In…/document interaction" is now unified under the same picker + `NSFileCoordinator` machinery. Old forensic write-ups referencing "Document Provider" artifacts are describing an earlier shape of the same subsystem.

> 🖥️ **macOS contrast:** Same `startAccessingSecurityScopedResource()` / security-scoped-bookmark dance exists in the macOS App Sandbox (Powerbox / `NSOpenPanel`). The difference is reach: a *non-sandboxed* macOS app skips all of it and opens any path. On iPadOS there is no non-sandboxed escape hatch — every app, always, goes through the broker.

### "On My iPad": the local container

The "On My iPad" (on a phone, "On My iPhone") location is the device's own local document store — the nearest analogue to a user-visible local folder, and the only Location whose bytes are always resident. It is itself implemented as a File Provider domain backed by a **shared app-group container**:

```
.../Containers/Shared/AppGroup/group.com.apple.FileProvider.LocalStorage/
        File Provider Storage/        ← the actual local files, real names/tree
        File Provider Storage/.Trash/ ← deleted local items (NOT shown in UI's "Recently Deleted")
```

Apps that opt to expose a Documents folder in Files (Pages, Keynote, VLC, …) appear here as subfolders. The Files app's own bookkeeping for this view lives in a small SQLite store:

| Store | Tables of interest | What it yields |
|---|---|---|
| **`smartfolders.db`** (Files app group container) | `filename` | The list of items in the "On My iPad" area |
| | `fp_folder_item` | An `NSKeyedArchiver` binary plist BLOB per item: creation/modification dates, file path, download-request state |
| | `hotfolders` | App libraries (Pages, Keynote, …) that have registered Documents folders into Files |

AirDrop-received files that a user "saves to Files" first land in the receiving app's **`Documents/Inbox/`** before being moved.

> 🔬 **Forensics note:** The `.Trash` under `group.com.apple.FileProvider.LocalStorage/File Provider Storage/` is a goldmine: items deleted from "On My iPad" persist there with their original names and tree, and — critically — they do **not** appear in the Files app's own "Recently Deleted" view, so a user who "emptied" Recently Deleted may still have them. Copy the database with `cp` before any `sqlite3` (even a `SELECT` opens a write lock and spawns `-wal`/`-shm`), and deserialize the `fp_folder_item` BLOBs (NSKeyedArchiver) to recover per-item timestamps.

### iCloud Drive (CloudDocs): the first-party provider

iCloud Drive is a File Provider domain whose backing daemon is **`bird`** (the CloudDocs daemon; its macOS-side CLI is **`brctl`**). Its on-device footprint:

```
/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/
        <user files & folders, original names>
        .Trash/                     ← iCloud Drive trash
        Downloads/                  ← Safari/other downloads target (iOS/iPadOS 13+)
        .<name>.<ext>.icloud        ← placeholder for an evicted (dataless) file

/private/var/mobile/Library/Application Support/CloudDocs/
        account.1                   ← contains the account DSID (numeric Apple Account id)
        session/db/client.db        ← table client_uploads: files this device uploaded
        session/db/server.db        ← server-side sync state / item records
```

`com~apple~CloudDocs` is the iCloud Drive *root*; third-party apps that store *their* data in iCloud appear as sibling `com~apple~<appcontainer>` directories under `Mobile Documents/`. The `~` substitution (for `.`) is the literal on-disk encoding.

> 🔬 **Forensics note:** `client.db`'s `client_uploads` table is direct evidence of **exfiltration via iCloud Drive** — it records what this device pushed *up*, by name and time, independent of whether the local copy still exists. Pair it with `account.1` (the DSID ties the activity to a specific Apple Account) and the `.Trash` contents. This survives even when the file itself has been removed locally. ⚖️ Cloud-side content for the same account is reachable only through iCloud acquisition, and **Advanced Data Protection (ADP), if enabled, end-to-end-encrypts iCloud Drive and breaks server-side acquisition** — see [[06-icloud-acquisition-and-advanced-data-protection]].

### External USB-C drives and SMB shares

iPadOS 13 turned the iPad into a machine that mounts storage. Both surfaces are presented through the File Provider mesh as **system-managed providers**, so the *same* dataless/materialization/security-scoped rules apply.

**USB-C / direct-attached storage.** A drive must have a **single data partition** formatted as one of: APFS, APFS (encrypted), HFS+ (Mac OS Extended), exFAT, FAT32, or FAT. iPadOS mounts these **read-write**; **NTFS is read-only**. There is no "eject by unmount kext" — the kernel's filesystem support handles it and the volume appears under *Locations*.

Mechanically, an attached volume is surfaced as a **system-managed File Provider domain** wrapping the kernel's filesystem support, which is why it inherits the same browse-is-metadata / open-is-materialize behavior and the same security-scoped picker access as any cloud provider — an app still cannot walk the SSD; it gets handed the file the user picked. The user can even reformat a USB-C drive (to APFS, exFAT, or MS-DOS FAT) from Files on USB-C iPads.

**SMB network shares.** Files has a built-in SMB client ("Connect to Server", `smb://host`). Mounted shares appear under *Shared* in the sidebar; credentials are stored in the **Keychain**, and the share behaves like any other provider domain (browse = metadata; open = materialize). The device retains the **recently-connected servers** so they re-list after a reboot; treat the exact store as acquisition-dependent and confirm its path against your image (recent-server lists have historically lived in a Files/`com.apple.DocumentsApp` preference plist) rather than assuming a fixed location.

When the iPad writes to a writable external volume (APFS/HFS+/exFAT), it can leave its **own** filesystem residue on the drive — e.g. a hidden trash directory for items deleted while mounted, plus standard volume metadata — so the *drive* carries evidence of what the iPad did to it, independent of the device's own stores. This mirrors the macOS "external drives carry their own `.fseventsd`/`.Trashes`" principle from the macOS forensics course; verify exactly what iPadOS 26 writes for a given filesystem before relying on a specific filename.

> 🔬 **Forensics note:** External and network storage are an evidence surface an *iPhone* exam essentially never produces but an *iPad* exam routinely must. Two angles: (1) the **drive itself** is separate evidence — image it independently; if it is APFS/HFS+ it may carry its own `.Trashes`/metadata written by iPadOS. (2) the **device** retains traces of the connection — materialized copies of opened files in the provider/working store, app "recents" pointing at `file://` URLs on the volume, SMB server hostnames/usernames in the Keychain and connection state, and behavioral records (Biome/`knowledgeC`-class app-context streams) of *when* the document app was foregrounded. Reconcile the two: a file present on the SSD plus a materialized copy + a foreground interval on the device places the document in front of the user at a time.

> ⚠️ **ADVANCED:** Plugging a suspect's USB-C drive into a live exhibit iPad to "see what's there" mounts it **read-write** (for APFS/HFS+/exFAT) and can update volume metadata, trash records, and timestamps on the drive. Treat the drive as its own exhibit: image it on a write-blocked workstation first; never explore it by attaching it to the device under examination.

### Where "Recents" and document-open history actually come from

The Files **Recents** tab is *not* a stored list you can dump. It is a live **`NSMetadataQuery`** (a Spotlight-style federated query) run across every enabled provider domain at view time, so the "artifact" is really the union of the providers' own caches plus behavioral stores. Likewise there is **no iOS equivalent of macOS's `com.apple.sharedfilelist` / `.sfl2` recent-documents lists**. Reconstruct document-open history from, in order of reliability:

1. **Materialized content + timestamps** in the provider/working store (it was opened ⇒ it was fetched).
2. **Per-app recents** — each editor keeps its own (often an `NSUserDefaults` plist or small DB inside *its* container) holding bookmarks/paths to recently opened documents.
3. **Behavioral stores** — Biome / SEGB streams and the `knowledgeC`-class app-usage records (which app was foreground, when) → see [[01-knowledgec-db-deep-dive]] and [[02-biome-and-segb-streams]].
4. **Unified logs / sysdiagnose** — `fileproviderd` and `bird` log materialization and sync events → see [[12-unified-logs-sysdiagnose-crash-network]].
5. **Security-scoped bookmarks** — an app that retained access to a user-picked file serialized a bookmark (commonly in its `NSUserDefaults` plist or a small store in its container); resolving it recovers the *original path/provider* of a document the user explicitly handed that app, which is strong "this user opened this specific file in this app" evidence.

Confirm the Files app itself is installed and find its container via `applicationState.db` (the system's per-app state DB keyed by `com.apple.DocumentsApp`); from there pivot to the app-group containers above.

### Forensic artifact map

A consolidated examiner's map of this layer (all paths device-relative; copy SQLite before querying):

| Artifact | Path (under the data volume) | Format | Yields |
|---|---|---|---|
| Files app identity | bundle `com.apple.DocumentsApp` | — | confirm via `applicationState.db` |
| On-My-iPad local files | `…/Containers/Shared/AppGroup/group.com.apple.FileProvider.LocalStorage/File Provider Storage/` | files (real names) | resident local documents |
| On-My-iPad trash | `…/File Provider Storage/.Trash/` | files | deleted-but-recoverable local docs (not in UI) |
| Files bookkeeping | `smartfolders.db` (Files app group container) | SQLite | `filename`, `fp_folder_item` (NSKeyedArchiver dates), `hotfolders` |
| Third-party provider cache | `…/File Provider Storage/<BASE64 account>/` | files | materialized cloud files per account |
| Provider private DB | `…/Containers/Data/Application/<uuid>/…/<Provider>.sqlite` | SQLite | offline/starred index, per-provider |
| iCloud Drive root | `…/Mobile Documents/com~apple~CloudDocs/` | files + `.Trash/` + `Downloads/` | resident iCloud Drive docs |
| iCloud eviction placeholder | `…/com~apple~CloudDocs/.<name>.<ext>.icloud` | binary plist | filename + size of a dataless file |
| CloudDocs account | `…/Application Support/CloudDocs/account.1` | plist | account **DSID** |
| CloudDocs uploads | `…/Application Support/CloudDocs/session/db/client.db` | SQLite | `client_uploads` (exfiltration) |
| CloudDocs sync state | `…/Application Support/CloudDocs/session/db/server.db` | SQLite | server-side item/sync records |
| AirDrop landing | `…/Containers/Data/Application/<uuid>/Documents/Inbox/` | files | received-then-saved files |

### Timestamps across the document layer

Like every Apple subsystem, the document layer mixes epochs — get them wrong and your timeline is decades off (see [[00-the-ios-timestamp-zoo]]):

| Source | Epoch / encoding | Convert |
|---|---|---|
| `fp_folder_item` BLOB (NSKeyedArchiver Cocoa dates) | **Mac Absolute Time** (seconds since 2001-01-01 UTC) | `+ 978307200` → Unix |
| CloudDocs `client.db` / `server.db` | often Mac Absolute Time; **verify per column** (some store Unix or text) | inspect before trusting |
| `.icloud` placeholder plist dates | Cocoa date (Mac Absolute) | `+ 978307200` |
| Filesystem mtime/ctime on materialized files | **Unix** (APFS) | as-is |
| `fileproviderd` / `bird` unified-log entries | wall clock in the log archive | use `log show` |

A materialized file's APFS mtime tells you when the *content* last changed on the device; the provider's recorded dates tell you about the *namespace* item. They legitimately differ — a freshly materialized older document gets a recent mtime but an old item date. Don't conflate "downloaded to device" with "authored/modified."

## Hands-on

> There is no on-device shell. Everything below runs on the **Mac**: against the Simulator's on-disk containers, against your own Mac's iCloud Drive as a *mechanism* analogue, or against a mounted public sample image.

### Locate the Files / On-My-iPad stores in a Simulator

```bash
# List booted simulators and pick a UDID
xcrun simctl list devices booted

UDID=<paste-udid>
SIMROOT=~/Library/Developer/CoreSimulator/Devices/$UDID/data

# The local On-My-iPad app-group container + its SQLite bookkeeping
find "$SIMROOT/Containers/Shared/AppGroup" \
     -iname "smartfolders.db" -o -iname "File Provider Storage" 2>/dev/null

# Inspect the smartfolders schema (copy first — SELECT still write-locks)
DB=$(find "$SIMROOT" -name smartfolders.db | head -1)
cp "$DB" /tmp/sf.db
sqlite3 /tmp/sf.db ".tables"
sqlite3 /tmp/sf.db "SELECT name FROM sqlite_master WHERE type='table';"
```

### Dissect a dataless iCloud placeholder on macOS (the same mechanism)

```bash
# On your Mac's iCloud Drive: force a file dataless, then read the placeholder/flag
brctl evict ~/Library/Mobile\ Documents/com~apple~CloudDocs/SomeBig.pdf
ls -lO ~/Library/Mobile\ Documents/com~apple~CloudDocs/SomeBig.pdf   # note 'dataless' flag
find ~/Library/Mobile\ Documents/com~apple~CloudDocs -flags dataless

# On iOS images the evicted file becomes a hidden ".name.ext.icloud" binary plist:
plutil -p "/path/to/image/.../com~apple~CloudDocs/.Report.pdf.icloud"
#  → keys for the original filename + logical size, NO content bytes

# brctl's live view of the CloudDocs namespace + sync state (macOS analogue of `bird`)
brctl log --wait --shorten        # stream sync events
brctl dump                        # dump the local CloudDocs database state
```

### Query CloudDocs sync evidence from a sample image

```bash
# Copy databases out of the (read-only) mounted image before querying
cp /mnt/img/private/var/mobile/Library/Application\ Support/CloudDocs/session/db/client.db /tmp/
sqlite3 /tmp/client.db ".schema client_uploads"
sqlite3 /tmp/client.db "SELECT * FROM client_uploads LIMIT 20;"

# The account DSID
plutil -p /mnt/img/private/var/mobile/Library/Application\ Support/CloudDocs/account.1
```

### Pull the documents container over USB (libimobiledevice / AFC)

The AFC channel exposes the *media* domain and, with the right service, app `Documents/` of apps that set `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` — useful for grabbing On-My-iPad-visible app folders without a full extraction. (Most File Provider working stores are **outside** AFC's reach and need a logical/full-filesystem acquisition — see [[04-logical-acquisition-with-libimobiledevice]].)

```bash
idevicepair pair                                  # trust must be established on-device
ideviceinstaller -l | grep -i documents           # find file-sharing-enabled apps
# Browse/copy an app's shared Documents over the house_arrest/AFC service:
ifuse --documents <bundle-id> /mnt/appdocs        # FUSE mount (or use pymobiledevice3 afc)
pymobiledevice3 afc pull /Documents /tmp/appdocs --bundle-id <bundle-id>
```

For the iCloud Drive root and the CloudDocs databases specifically, AFC's media domain is not enough — those sit under `/private/var/mobile/Library/…` and require a logical-plus or full-filesystem acquisition. Plan the acquisition method around *which* part of this layer you need (see [[01-the-acquisition-taxonomy]]).

### Drive the whole layer with iLEAPP

```bash
# iLEAPP (Brignoni) ships parsers for the Files app / iCloud / File Provider artifacts
pip install ileapp
ileapp -t fs -i /path/to/extracted/filesystem -o /tmp/ileapp_out
# Open the report; look for the "Files App", "iCloudDrive", "File Provider" sections
```

### Mine materialization & sync events from a sysdiagnose / log archive

```bash
# From a device sysdiagnose (or a collected .logarchive), fileproviderd and bird
# log materialization, eviction, and sync activity by item identifier:
log show --archive /path/to/sysdiagnose.logarchive \
  --predicate 'process == "fileproviderd" OR process == "bird"' \
  --info --style syslog | grep -iE 'materializ|evict|fetchContents|upload|conflict' | head -40
```

## 🧪 Labs

> Every lab is **device-free**. Each names its substrate and its fidelity caveat. The recurring caveat for this lesson: **the Simulator runs macOS frameworks and has no real cloud account, no third-party File Provider extensions, no `bird`/`fileproviderd` device behavior, and no USB-C/SMB mounting** — it faithfully reproduces the *local container structure* (On My iPad, `File Provider Storage`, `smartfolders.db`) but **not** materialization, eviction, cloud sync, or external mounts. Those are taught from a sample image or from your Mac's own CloudDocs as a mechanism analogue.

### Lab 1 — Map the local document container (Simulator)

**Substrate:** Xcode Simulator. **Caveat:** local structure only; no provider domains, no cloud, no external drives.

1. Boot a simulator (`xcrun simctl boot <UDID>`), open the Files app in it, and create a folder + a text file under "On My iPad".
2. On the Mac, `find` the `group.com.apple.FileProvider.LocalStorage` container under that device's `data/Containers/Shared/AppGroup/` and confirm your file appears under `File Provider Storage/` with its real name.
3. Delete the file in the Simulator's Files UI. Re-`find`: confirm it moved into `File Provider Storage/.Trash/` even if the UI shows nothing.
4. `cp` `smartfolders.db` and dump the `filename` and `fp_folder_item` tables. Deserialize one `fp_folder_item` BLOB (`plutil -p` after extracting the BLOB, or a tiny `NSKeyedUnarchiver` script) and read its timestamps.

### Lab 2 — Dataless files, placeholders, and the eviction lifecycle (macOS analogue)

**Substrate:** your Mac's iCloud Drive (read-only walkthrough of the *mechanism*). **Caveat:** macOS exposes the dataless lifecycle directly; iPadOS hides it behind UI but uses the identical File Provider machinery.

1. Pick (or copy in) a large file in `~/Library/Mobile Documents/com~apple~CloudDocs/`. Run `find . -flags dataless` — it should not be listed yet.
2. `brctl evict <file>`; re-run the `find` and `ls -lO` — confirm the `dataless` flag now appears. You have just reproduced what "Remove Download" does on iPad.
3. Open the file (double-click) to trigger **materialization**; watch `brctl log --wait` print the fetch. Re-check the flag — it is gone.
4. On a **sample iOS image**, locate a `.<name>.<ext>.icloud` placeholder under `com~apple~CloudDocs`, `plutil -p` it, and record the original filename + size. Write one sentence on what you can and *cannot* assert about that file from the placeholder alone (you have existence + size, **not** content).

### Lab 3 — CloudDocs sync & the On-My-iPad trash on a public image

**Substrate:** a public sample forensic image (e.g. a Josh Hickman iOS/iPadOS reference image). **Caveat:** the encrypted/lock-state behavior is real here; the Simulator cannot produce these device-only stores.

1. Mount the image read-only. Copy `CloudDocs/session/db/client.db` and `server.db` out before touching them.
2. `sqlite3` the `client_uploads` table — list every file the device uploaded to iCloud Drive with its timestamp. Note that some rows may name files no longer present locally.
3. Read `account.1` for the DSID; tie the upload activity to the account.
4. Walk `File Provider Storage/.Trash/` (On My iPad) and `com~apple~CloudDocs/.Trash/` (iCloud Drive). Build a short table of "deleted but recoverable" documents from both trashes.
5. Run **iLEAPP** against the full extraction and compare its "Files App"/"iCloud" sections to what you found by hand. Note anything iLEAPP surfaced that you missed (and vice versa).

### Lab 4 — Attribute a third-party provider cache (public image, read-only walkthrough)

**Substrate:** a public sample image that includes a third-party cloud app (or the iLEAPP test data). **Caveat:** the Simulator cannot register real provider domains, so this is image-only.

1. Under `group.com.apple.FileProvider.LocalStorage/File Provider Storage/`, list the immediate subfolders. Identify the **BASE64-encoded** account/domain folders (vs. the plain On-My-iPad tree).
2. `echo '<folder-name>' | base64 -D` (macOS) to decode the account identifier. Record which provider/account each cache belongs to.
3. Find the same provider app's own container under `Containers/Data/Application/<uuid>/` and locate its private `*.sqlite` index. Query it for offline/starred files.
4. Reconcile: list files that appear in the **app's DB** but have **no materialized copy** in `File Provider Storage` (enumerated-not-resident), and any materialized files the app DB no longer references (orphaned cache). Write one line on what each discrepancy implies.

## Pitfalls & gotchas

- **"It's in Files, so it's on the device" is false.** Files lists *enumerated* items, most of which may be **dataless**. A logical extraction captures materialized bytes + placeholders, not the whole namespace. Always separate "existed in the namespace" from "content was on the device."
- **The Files UI's "Recently Deleted" ≠ the on-disk trash.** Items in `File Provider Storage/.Trash/` (On My iPad) can persist even after a user empties the visible Recently Deleted. Check the disk, not the UI's model.
- **`Recents` cannot be dumped.** It is a live `NSMetadataQuery`, not a stored list. Don't go hunting for a `recents.db`; reconstruct document-open history from provider caches + per-app recents + Biome/`knowledgeC` behavioral streams + `fileproviderd`/`bird` logs.
- **There is no `.sfl2` / `sharedfilelist` on iOS.** The macOS recent-documents reflex has no direct counterpart; each app rolls its own recents inside its container.
- **Mounting a suspect USB-C drive on the exhibit device contaminates the drive.** iPadOS mounts APFS/HFS+/exFAT **read-write**. Image the drive on a write-blocked workstation as its own exhibit; never browse it via the device.
- **NTFS is read-only; multi-partition drives won't mount.** A drive that "doesn't show up" is often multi-partition or NTFS-with-attempted-write — not a device fault.
- **ADP changes the cloud half entirely.** With Advanced Data Protection on, iCloud Drive is E2E-encrypted and server-side acquisition yields nothing useful; on-device materialized copies and the local `CloudDocs` databases become your only iCloud Drive evidence.
- **Copy before you query.** Every `sqlite3` against `smartfolders.db`, `client.db`, `server.db` must run on a `cp`'d copy — a bare `SELECT` write-locks the DB and creates `-wal`/`-shm`, altering the evidence.
- **The Simulator lies about the cloud/provider/external layers.** It reproduces local container *layout* only. Don't infer materialization, eviction, sync, or external-mount behavior from Simulator observations — use a sample image.
- **Conflict copies and working-set residue hide in plain sight.** A "conflicted copy" is a real on-disk file the user never deliberately created, and working-set metadata can name files whose content is long gone. Both routinely survive cleanup — search for them explicitly.
- **Core Spotlight outlives the file's bytes.** A snippet/title donated at last-index time can name and partially reveal a document that is now dataless or deleted. Treat the search index as an independent artifact, and verify its iOS 26 store paths against the actual acquisition.
- **A third-party provider is two artifacts.** Parse both the system `File Provider Storage/<base64>/` working store *and* the provider app's private `*.sqlite` in its own container — they can disagree, and each names files the other doesn't.
- **Open-in-place vs. import is not cosmetic.** An in-place edit leaves no copy in the editing app and changes the provider source; an import forks an independent copy into the app's sandbox. Decide which path a document took before concluding "the only copy is here."
- **Don't trust a file's mtime as its authored time.** A just-materialized old document carries a recent APFS mtime; the provider's item date is the one that reflects authorship/last namespace change. Carry both.

## Key takeaways

- The Files app owns no files. It is a **brokered, federated viewer** over File Provider extensions coordinated by **`fileproviderd`**; every Location is one or more `NSFileProviderDomain`s, each fully sandboxed.
- **Replicated** providers (`NSFileProviderReplicatedExtension`) vend a metadata item tree and let the system cache bytes; **non-replicated** legacy providers use a shared **`File Provider Storage`** folder.
- **Dataless/materialization** is the central concept: enumerated ≠ resident. Evicted iCloud files leave `.<name>.<ext>.icloud` placeholders proving existence + size, not content.
- Apps reach files only through the **out-of-process document picker** → **security-scoped URL** + bookmark. Files is system-mediated consent, not a license to roam — the sandbox is never relaxed.
- **"On My iPad"** is the local store: `group.com.apple.FileProvider.LocalStorage/File Provider Storage/` (+ its `.Trash/`), tracked by **`smartfolders.db`** (`filename`, `fp_folder_item`, `hotfolders`).
- **iCloud Drive** is the `bird`/CloudDocs provider at `Mobile Documents/com~apple~CloudDocs/`; `CloudDocs/session/db/client.db` (`client_uploads`) is direct upload/exfiltration evidence and `account.1` carries the DSID.
- **External USB-C (APFS/HFS+/exFAT/FAT r-w, NTFS r-o) and SMB** make the iPad a storage host — an evidence surface absent on iPhone exams; treat attached drives as their own exhibits and correlate device-side materialized copies + behavioral timing.
- Reconstruct **document-open history** from materialized caches + per-app recents + Biome/`knowledgeC` + `fileproviderd`/`bird` logs, because iOS has **no** `sharedfilelist`/`.sfl2` equivalent.

## Terms introduced

| Term | Definition |
|---|---|
| File Provider framework | Apple's API (`NSFileProvider*`) for exposing app/cloud/external storage into Files/Finder as sandboxed providers |
| `fileproviderd` | System daemon that registers provider domains, brokers enumeration/materialization, and manages the working store |
| `NSFileProviderDomain` | One provider "Location" in the sidebar; an extension can vend several, each independent |
| `NSFileProviderExtension` | Principal class of a legacy **non-replicated** provider (exposes a system-managed working folder) |
| `NSFileProviderReplicatedExtension` | Principal class of a modern **replicated** provider (vends a metadata item tree; system mirrors/caches) |
| Materialization | On-demand fetch of a dataless item's content (`fetchContents` / `startProvidingItem`) when it is opened |
| Dataless file | A file present as fully-described metadata with no content bytes on the device until materialized |
| `.icloud` placeholder | Hidden `.<name>.<ext>.icloud` binary plist left for an evicted iCloud Drive file (name + size, no content) |
| `bird` / CloudDocs | The iCloud Drive daemon (macOS CLI `brctl`); backing store `Mobile Documents/com~apple~CloudDocs/` |
| `UIDocumentPickerViewController` | Out-of-process system picker that returns a security-scoped URL for a user-chosen file |
| Security-scoped URL/bookmark | A narrow, per-file access grant (`startAccessingSecurityScopedResource`) bracketing sandboxed access |
| `smartfolders.db` | Files app SQLite store for "On My iPad" (`filename`, `fp_folder_item`, `hotfolders` tables) |
| `File Provider Storage` | Local app-group folder (`group.com.apple.FileProvider.LocalStorage`) holding On-My-iPad bytes + `.Trash/` |
| `client_uploads` | Table in CloudDocs `client.db` recording files this device uploaded to iCloud Drive |
| `NSFileProviderItemCapabilities` | Per-item bitmask (read/write/rename/move/trash/delete/evict) that gates allowed operations |
| Working set | The always-materialized metadata set (Recents/Favorites/Tagged/recent) the system keeps for instant offline rendering |
| Conflict copy | A second item a provider creates when an offline edit can't be reconciled cleanly; preserves a divergent version |
| Core Spotlight | The on-device search index providers donate items to; can retain names/snippets of now-dataless or deleted files |

## Further reading

- Apple Developer — **File Provider** framework (`NSFileProviderReplicatedExtension`, `NSFileProviderDomain`, `NSFileProviderItem`, materialization), and **Document-based apps** (`UIDocumentPickerViewController`, `UIDocumentBrowserViewController`, security-scoped bookmarks).
- Apple Platform Security Guide — Data Protection and the app sandbox model that File Provider operates within.
- Apple Support — "Connect external storage devices to iPad" and "Transfer files from iPad to a storage device, a server, or the cloud" (supported filesystems, SMB).
- `man brctl`, `man plutil`, `man sqlite3` — exact flags on your macOS version; `brctl log`/`brctl dump` for the CloudDocs analogue.
- d204n6 (Ian Whiffin) — "iOS: The Files App" (smartfolders.db tables, File Provider Storage, AirDrop Inbox).
- Magnet Forensics — "Exploring the Files App in iOS" (File Provider Storage, third-party providers, BASE64 account folders).
- digital-forensics.it (Mattia Epifani) — "A first look at iOS 18 forensics" (CloudDocs `client.db`/`server.db` over logical acquisition).
- Alexis Brignoni — **iLEAPP** (Files/iCloud/File Provider parsers); Sarah Edwards — **APOLLO** + mac4n6 (behavioral correlation for open history).
- Claudio Cambra — "Build your own cloud sync using Apple's FileProvider APIs" (replicated-extension implementation walkthrough).

---
*Related lessons: [[00-how-ipados-diverges-from-ios]] | [[00-app-sandbox-and-filesystem-layout]] | [[08-filesystem-layout-and-containers]] | [[06-icloud-acquisition-and-advanced-data-protection]] | [[01-knowledgec-db-deep-dive]] | [[01-simulator-internals-and-on-disk-filesystem]]*
