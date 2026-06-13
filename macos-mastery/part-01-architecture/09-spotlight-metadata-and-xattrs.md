---
title: Spotlight, metadata & extended attributes
part: P01 Architecture
est_time: 50 min read + 40 min labs
prerequisites: [03-apfs-deep-dive, 04-filesystem-layout-and-domains, 08-security-architecture]
tags: [macos, spotlight, metadata, xattrs, forensics, mdfind, mdls, quarantine, finder-tags]
---

# Spotlight, metadata & extended attributes

> **In one sentence:** Spotlight is a per-volume metadata database built by a daemon pipeline that calls importer plugins to extract structured `kMDItem*` attributes from every file — and extended attributes (xattrs) are a parallel per-file key-value store baked into the filesystem itself that carry quarantine flags, Finder tags, download provenance, and legacy Mac resource-fork data.

---

## Why this matters

Two orthogonal systems describe files on macOS beyond the POSIX inode: the **Spotlight index** (a volume-wide, full-text searchable database of extracted metadata) and **extended attributes** (per-file key-value pairs stored in the filesystem). For a forensics professional:

- Both are rich artifact sources. The quarantine xattr captures _who_ downloaded a file, _when_, and from _what URL_. The Spotlight index preserves metadata about files even after deletion (until the next re-index). `.DS_Store` carries folder view state that leaks filenames. Resource forks survive as `._` AppleDouble files on FAT and SMB shares.
- For power usage: `mdfind` can replace `find` for semantic searches. Smart Folders are just saved `mdfind` predicates. Hazel, Automator, and Shortcuts can trigger on metadata changes via the `NSMetadataQuery` API.

If you've used NTFS Alternate Data Streams on Windows, xattrs are the macOS analogue — but more pervasive, more standardized, and more forensically visible.

> 🪟 **Windows contrast:** NTFS stores extended metadata in Alternate Data Streams (ADS), accessed with `Get-Item -Stream *`. macOS xattrs are surfaced natively by the filesystem and via `xattr(1)`. Windows has its own quarantine-like Zone.Identifier stream (`ZoneId=3` for internet); macOS uses `com.apple.quarantine`. Windows Search / Windows Indexing Service is the rough functional equivalent of Spotlight, but lives in `%ProgramData%\Microsoft\Search\Data\Applications\Windows\` rather than per-volume.

---

## Concepts

### 1. The Spotlight daemon pipeline

Spotlight is not a single process. It is a pipeline of daemons orchestrated by `mds` (Metadata Server):

```
File system event
       │
       ▼
   mds (launchd agent)            — policy, queue management, query server
       │   spawns
       ▼
  mdworker_shared                 — per-file metadata extraction worker
       │   calls
       ▼
  .mdimporter plugin              — UTI-matched, extracts kMDItem* attributes
       │
       ▼
  mds_stores                      — compresses & writes into .Spotlight-V100
       │
       ▼
  mediaanalysisd (MAD)            — optional: ML-driven text/image extraction
```

**`mds`** — the supervisor. It listens to FSEvents for file creation/modification, manages the indexing queue, and answers `mdfind` queries. Launched by launchd; its plist is at `/System/Library/LaunchDaemons/com.apple.metadata.mds.plist`. On Apple Silicon this runs entirely in the user session as a per-user agent (also `com.apple.metadata.mds` in `LaunchAgents`).

**`mdworker_shared`** (previously `mdworker`) — a sandboxed worker process spawned per-file or per-batch. It loads the appropriate `.mdimporter` plugin and returns extracted attributes to `mds`. You will see many of these in Activity Monitor when indexing is active. Multiple instances run in parallel.

**`mds_stores`** — handles the actual write path into the index store; compresses content and writes the B-tree structures under `.Spotlight-V100`. This separates the extraction hot path from the disk-write path.

**`mediaanalysisd`** — optional AI-layer daemon that performs OCR on images, processes PDFs for semantic content, and performs embedding tasks. Active on Apple Silicon. Its results (kMDItemTextContent from image OCR, for example) are fed back into the index.

**`spotlightknowledged`** — maintains the ML-driven Spotlight Suggestions knowledge graph (Siri intelligence integration). Brief bursts of activity after indexing.

#### Importer plugins (.mdimporter)

Importers are bundles conforming to the Spotlight importer API. They receive a file path, open the file, and return a dictionary of `kMDItem*` attributes. Locations searched in order:

| Path | Scope |
|---|---|
| `/System/Library/Spotlight/` | Apple-bundled (sealed SSV; read-only) |
| `/Library/Spotlight/` | System-wide third-party |
| `~/Library/Spotlight/` | Per-user third-party |
| Inside `.app` bundle: `Contents/Library/Spotlight/` | App-bundled importer (registered by LaunchServices) |

Key system importers: `RichText.mdimporter` (RTF, plain text, HTML), `PDF.mdimporter`, `Image.mdimporter` (JPEG/EXIF), `Office.mdimporter` (DOCX/XLSX), `iWork.mdimporter` (Pages/Numbers/Keynote).

List all installed importers:
```bash
mdimport -L
```

Test how a specific file will be indexed (debug level 3 is most verbose):
```bash
mdimport -t -d3 /path/to/file.pdf
```

> 🔬 **Forensics note:** Third-party importers in `~/Library/Spotlight/` or `/Library/Spotlight/` are a persistence vector. A malicious `.mdimporter` runs sandboxed but still executes code on every new file of the matching UTI. Check these locations during a compromise investigation.

### 2. The .Spotlight-V100 index store

Every indexed volume carries its index in a hidden top-level directory: `/.Spotlight-V100/`. On the boot volume this is `/.Spotlight-V100/` (inside the Data volume in an APFS sealed-system-volume setup). External drives and mounted volumes each get their own index.

Internal structure (you need `sudo` to ls it):
```
.Spotlight-V100/
├── Store-V2/
│   ├── <UUID>/
│   │   ├── 0.indexHead          ← B-tree root and header
│   │   ├── 0.indexIds           ← file-ID to inode mapping
│   │   ├── 0.indexGroups        ← attribute group store
│   │   ├── 0.indexPositions     ← token position data for full-text
│   │   ├── 0.indexTermIds       ← term dictionary
│   │   └── ...
│   └── journals/
│       └── *.journal            ← WAL-style journal for crash recovery
└── VolumeConfig.plist
```

The format is a proprietary B-tree. Open-source readers (`mdimport`, `mdfind`) access it via the `CoreServices` framework. Third-party forensics tools (Axiom, Recon Imager, Autopsy with macOS plugins) can parse `.Spotlight-V100` directly and often recover metadata for deleted files if the inode slot was reused but the Spotlight entry wasn't yet evicted.

> 🔬 **Forensics note:** Spotlight indexes are a **goldmine for deleted file recovery**. The index stores `kMDItemPath`, `kMDItemContentCreationDate`, `kMDItemLastUsedDate`, author, GPS coordinates, email recipients, and other attributes extracted at index time. Files deleted after indexing leave stale entries until the next full re-index. Acquire `.Spotlight-V100` as part of any macOS image.

### 3. Metadata attributes (kMDItem*)

Spotlight attributes follow a `kMDItem` prefix convention defined in `CoreServices/MDItem.h`. Selected forensically and operationally important attributes:

| Attribute | Type | Notes |
|---|---|---|
| `kMDItemPath` | String | Absolute POSIX path at last index time |
| `kMDItemFSName` | String | Filename |
| `kMDItemContentType` | String | UTI (e.g., `public.jpeg`) |
| `kMDItemContentCreationDate` | Date | Filesystem creation time |
| `kMDItemContentModificationDate` | Date | Filesystem mtime |
| `kMDItemLastUsedDate` | Date | Last opened (from LaunchServices) |
| `kMDItemWhereFroms` | Array of strings | Download source URLs (from quarantine xattr) |
| `kMDItemDownloadedDate` | Date | When downloaded |
| `kMDItemUserTags` | Array of strings | Finder color/text tags |
| `kMDItemAuthors` | Array of strings | Document author field |
| `kMDItemCreator` | String | Creating application |
| `kMDItemTextContent` | String | Full-text body (indexed but not returned by mdls) |
| `kMDItemLatitude` / `kMDItemLongitude` | Real | EXIF GPS coordinates from photos |
| `kMDItemKeywords` | Array of strings | Document keywords |
| `kMDItemRecipients` | Array of strings | Email recipients (Mail.app) |
| `kMDItemEmailAddresses` | Array of strings | Email addresses in document |
| `kMDItemIsScreenCapture` | Boolean | Screenshot flag |
| `kMDItemScreenCaptureType` | String | `display`, `selection`, `window` |

`kMDItemTextContent` is stored in the index but deliberately excluded from `mdls` output to avoid leaking document contents. Use `mdfind` to search it.

### 4. mdfind — semantic file search

`mdfind` is the CLI interface to Spotlight search. Syntax:

```bash
mdfind [-live] [-count] [-onlyin <dir>] [-name <name>] '<predicate>'
```

Key operators:
- `==` exact, `!=` not equal
- `<`, `>`, `<=`, `>=` for dates/numbers
- `CONTAINS` substring, `BEGINSWITH`, `ENDSWITH`
- `[c]` case-insensitive, `[d]` diacritic-insensitive, `[cd]` both
- `&&` AND, `||` OR, `!` NOT

Practical examples:

```bash
# Find all files whose full text contains "confidential"
mdfind 'kMDItemTextContent == "confidential"'

# Find PDFs modified in the last 7 days in Downloads
mdfind -onlyin ~/Downloads 'kMDItemContentType == "com.adobe.pdf" && kMDItemContentModificationDate >= $time.today(-7)'

# Find images with GPS coordinates (geotagged photos)
mdfind 'kMDItemLatitude > 0'

# Find files downloaded from a specific domain
mdfind 'kMDItemWhereFroms == "*github.com*"'

# Find screenshots taken today
mdfind 'kMDItemIsScreenCapture == 1 && kMDItemContentCreationDate >= $time.today'

# Live mode: print matches as they are indexed (useful for watching a folder being indexed)
mdfind -live -onlyin ~/Desktop 'kMDItemContentType == "public.jpeg"'

# Count only
mdfind -count 'kMDItemContentType == "public.mp4"'

# Search by filename (faster; bypasses full-text index)
mdfind -name "invoice"
```

`$time.today`, `$time.yesterday`, `$time.this_week`, `$time.this_month`, and `$time.now(-N)` (N in seconds) are supported time predicates.

### 5. mdls — inspect a file's indexed metadata

```bash
mdls /path/to/file
```

Dumps all `kMDItem*` attributes Spotlight has indexed for that file. The output format is readable key-value pairs. To query a specific attribute:

```bash
mdls -name kMDItemWhereFroms ~/Downloads/SomeInstaller.dmg
mdls -name kMDItemContentCreationDate -name kMDItemAuthors ~/Documents/report.pdf
```

To get raw attribute values (useful in scripts):

```bash
mdls -raw -name kMDItemWhereFroms ~/Downloads/file.zip
```

If an attribute shows `(null)`, the importer either didn't extract it or the file hasn't been indexed yet.

### 6. mdutil — index management

`mdutil` controls Spotlight indexing at the volume level. It speaks to `mds` directly.

```bash
# Check indexing status of the boot volume
mdutil -s /

# Check all mounted volumes
mdutil -sa

# Disable indexing on a volume (e.g., external drive you don't want indexed)
sudo mdutil -i off /Volumes/ExternalDrive

# Enable indexing
sudo mdutil -i on /Volumes/ExternalDrive

# Erase and rebuild the index (most thorough fix for stale/corrupt index)
sudo mdutil -E /

# Erase and rebuild for a specific volume
sudo mdutil -E /Volumes/ExternalDrive

# Print the full index store path (verbose)
mdutil -sv /
```

Expected output from `mdutil -s /`:
```
/:
    Indexing enabled.
```

> ⚠️ **ADVANCED:** `sudo mdutil -E /` wipes and rebuilds the entire boot-volume Spotlight index. This is non-destructive to your files but the index rebuild takes 15–60 minutes and temporarily degrades Spotlight search quality. Rollback: just wait for reindex to complete; there is no state to restore. Use this when `mdfind` is returning stale or wrong results, or after migrating files in bulk.

### 7. The `.spotlight_temp` and privacy exclusion list

Files/directories can be excluded from indexing two ways:

1. **System Preferences / System Settings → Siri & Spotlight → Spotlight Privacy** — adds the path to `/Library/Preferences/com.apple.spotlight.plist` under the `Privacy` key.
2. Placing a `.metadata_never_index` file or a `.Spotlight-V100` file at the root of a mounted volume signals `mds` to skip that volume.

Programmatically read the exclusion list:
```bash
defaults read /Library/Preferences/com.apple.spotlight.plist Privacy
```

> 🔬 **Forensics note:** An adversary that knows about Spotlight can exclude their working directory from indexing. The presence of `.metadata_never_index` on a volume, or a path in the Privacy exclusion list that contains sensitive or unusual directories, is itself a forensic indicator.

---

## Extended attributes (xattrs)

### What they are

Extended attributes are arbitrary key-value pairs attached to a file or directory at the filesystem level. They are part of the POSIX standard (`getxattr(2)`, `setxattr(2)`, `listxattr(2)`, `removexattr(2)`) and fully supported by APFS, HFS+, and most Linux filesystems. The value is opaque bytes; the key is a UTF-8 string up to 127 characters.

On APFS, xattrs are stored inline in the B-tree node for small values (under ~3.8KB) or as a separate overflow extent for larger ones. They are part of the file record and travel with the file on APFS→APFS copies via `cp -p`, `ditto`, and `rsync -X`.

`ls -l@` shows an `@` after the permissions string for files with xattrs:
```
-rw-r--r--@  1 bronty13  staff  2048 Jun 13 09:00 downloaded.zip
```

### Core xattrs you will encounter

#### com.apple.quarantine

Set by any Gatekeeper-aware application (Safari, Chrome, Firefox, curl with Gatekeeper hooks, Mail, Messages, AirDrop receiver) when it writes a file downloaded from a network source. `mds` also propagates quarantine to the Spotlight attribute `kMDItemWhereFroms`.

Format: a semicolon-delimited string:
```
0181;67794cd5;Chrome;78B4F60F-4838-431E-8A72-6C666B15E5A6
```

Fields:
1. **Flags** (hex) — quarantine flags; `0081` = first-party downloader, `0181` = downloaded via browser. Bit 15 (`0x8000`) set = user has already seen and dismissed the Gatekeeper warning.
2. **Timestamp** (hex Unix epoch) — when the file was quarantined.
3. **Quarantine agent** — bundle ID or human-readable name of the downloading application.
4. **UUID** — quarantine event UUID, cross-referenced in `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` (SQLite).

Read it:
```bash
xattr -p com.apple.quarantine ~/Downloads/SomeApp.dmg
```

The quarantine database:
```bash
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  "SELECT datetime(LSQuarantineTimeStamp+978307200,'unixepoch','localtime'),
          LSQuarantineAgentName, LSQuarantineDataURLString,
          LSQuarantineOriginURLString
   FROM LSQuarantineEvent
   ORDER BY LSQuarantineTimeStamp DESC
   LIMIT 20;"
```

(The `+978307200` converts Apple's Core Data epoch — seconds since 2001-01-01 — to Unix epoch.)

> 🔬 **Forensics note:** `QuarantineEventsV2` persists independently of the downloaded file. Even if a file is deleted, its quarantine event record and download URL remain in this SQLite database until macOS prunes it (entries older than ~90 days are pruned). This is an excellent artifact for establishing "this user downloaded X from Y on date Z" even post-deletion.

To strip quarantine (required before Gatekeeper will let you open unsigned software):
```bash
xattr -d com.apple.quarantine /path/to/app.app
# Or recursively for an app bundle:
xattr -rd com.apple.quarantine /Applications/SomeTool.app
```

> 🔬 **Forensics note:** Evidence of quarantine removal is itself significant. There is no system log of `xattr -d` calls by default; however, FSEvents will log attribute-change events on the file. If an attacker stripped quarantine before launching malware, the xattr simply won't be present — absence of quarantine on a file that should have it (e.g., a `.dmg` in the Downloads folder) is an indicator.

#### com.apple.metadata:kMDItemWhereFroms

Stores the download URL(s) as a binary plist array. Set by Safari, Chrome, Firefox, curl, and other download clients. Contains two elements: the direct URL of the file, and the referring page URL.

Read as a binary plist:
```bash
xattr -p com.apple.metadata:kMDItemWhereFroms ~/Downloads/installer.dmg \
  | xxd -r -p | plutil -convert xml1 -o - -
```

Or leverage Spotlight (same data, more conveniently):
```bash
mdls -name kMDItemWhereFroms ~/Downloads/installer.dmg
```

#### com.apple.metadata:_kMDItemUserTags

Stores Finder color tags and custom text tags. Format: binary plist array of strings. Tag strings with a color use the format `TagName\n7` where `\n7` is a literal newline followed by the color index (0=none, 1=gray, 2=green, 3=purple, 4=blue, 5=yellow, 6=red, 7=orange).

```bash
# Read tags on a file
xattr -p com.apple.metadata:_kMDItemUserTags ~/Desktop/report.pdf \
  | xxd -r -p | plutil -convert xml1 -o - -

# Find all Red-tagged files via Spotlight
mdfind 'kMDItemUserTags == "Red"'

# Find files tagged "Forensics" anywhere on the system
mdfind 'kMDItemUserTags == "Forensics"'
```

#### com.apple.FinderInfo

A 32-byte binary blob carrying legacy HFS+ Finder Info: the 4-byte type code, 4-byte creator code, Finder flags (stationery, invisible, has-custom-icon, name-locked, etc.), and icon position within a window. On APFS and modern macOS most of this is vestigial, but the **invisible flag** (bit 14 of the Finder flags word at offset 8) is still honored by Finder, used by macOS to hide system files from non-technical users, and can be set by malware for persistence.

```bash
# Read raw FinderInfo (hex dump)
xattr -px com.apple.FinderInfo /path/to/file

# Check if invisible flag is set (byte 9, bit 6 = 0x40 in flags word at bytes 8-9)
# Easier: use GetFileInfo
GetFileInfo -V /path/to/file   # shows type/creator/flags in human form
```

#### com.apple.ResourceFork

The classic Mac OS resource fork — structured binary data containing icons, string tables, code segments, dialog boxes, and application resources — now stored as an xattr on APFS/HFS+. On modern apps this is nearly empty or absent (everything is in the app bundle). But legacy applications and some document types still carry resource forks.

Access via the synthetic `/..namedfork/rsrc` path:
```bash
# Check size
ls -l "file/..namedfork/rsrc"

# Read raw resource fork
cat "file/..namedfork/rsrc" > rsrc_dump.bin

# Or via xattr
xattr -l file | grep ResourceFork
```

> 🪟 **Windows contrast:** The resource fork is the Mac equivalent of NTFS ADS (e.g., `file.exe:StreamName`). The forensic discipline is similar: check for non-zero size resource forks on suspicious files, as they can hide data.

### AppleDouble files — resource forks on non-native volumes

When macOS writes a file to a filesystem that doesn't natively support xattrs or resource forks (FAT32, ExFAT, SMB shares depending on server support), it splits the file into two: the data fork as `filename` and the metadata/resource-fork as `._filename` (the **AppleDouble** format, defined in Apple Technical Note TN1150).

These `._` files:
- Appear on USB drives formatted FAT32, Windows SMB shares, and some NAS
- Contain a binary AppleDouble header, FinderInfo block, and resource fork data
- Are created by the macOS kernel's `copyfile(3)` machinery automatically
- Should be hidden from non-Mac users but often aren't

> 🔬 **Forensics note:** `._` files on a recovered FAT32 drive prove the volume was mounted by macOS and written to. The AppleDouble header contains a creation timestamp and, if the file was quarantined, the quarantine bytes. Critically: the `._` file for a deleted file often **survives** after the main file is deleted, leaking the filename and metadata.

List `._` files on an attached volume:
```bash
find /Volumes/ExternalDrive -name "._*" -not -path "*/.Spotlight-V100/*"
```

Clean them (if the drive is yours and you want to send it to Windows users):
```bash
dot_clean -m /Volumes/ExternalDrive
```

### .DS_Store — folder view state

`.DS_Store` is a binary file created by Finder in every directory it opens that stores the folder's view settings: icon positions, sort order, background image, view type (icon/list/column/gallery), sidebar width, and crucially: **the names of files that Finder observed in the directory**, including files that may have since been deleted.

Format: a proprietary B-tree blob. Parse it with:
- `brew install dsstore` + `dsstore ls .DS_Store`
- Python: the `ds_store` PyPI package
- `strings .DS_Store | grep -v "^\.$"` for a quick dirty dump

> 🔬 **Forensics note:** `.DS_Store` leaks directory contents to anyone who can read it. Web servers that serve static files will serve `.DS_Store` too (classic OSINT source for web path enumeration). On a forensic image, `.DS_Store` files prove which directories Finder opened, and what files were present at the time — even if those files are now gone. In high-profile cases, `.DS_Store` files on USB drives or cloud storage have revealed directory trees of classified or sensitive data.

---

## Hands-on (CLI & GUI)

### Inspecting xattrs

```bash
# List all xattrs on a file (names and hex values)
xattr -l ~/Downloads/SomeFile.dmg

# Just the names
xattr ~/Downloads/SomeFile.dmg

# Read a specific attribute as printable string
xattr -p com.apple.quarantine ~/Downloads/SomeFile.dmg

# Read binary plist attribute and convert to XML for reading
xattr -p com.apple.metadata:kMDItemWhereFroms ~/Downloads/SomeFile.dmg \
  | xxd -r -p | plutil -convert xml1 -o - -

# Show all files in current directory with xattrs (ls @ flag)
ls -la@

# Recursively list xattrs of all files in a directory
xattr -rl ~/Downloads/
```

### Metadata queries

```bash
# What attributes does Spotlight know about a file?
mdls ~/Downloads/SomeFile.dmg

# Search for all files downloaded from the web in the last 30 days
mdfind 'kMDItemWhereFroms != "" && kMDItemDownloadedDate >= $time.today(-30)'

# Find all email messages sent to a specific address
mdfind 'kMDItemRecipients == "boss@example.com"'

# Find geotagged photos
mdfind -onlyin ~/Pictures 'kMDItemLatitude > 0 && kMDItemLongitude != 0'

# Find files whose content contains a keyword, limited to a directory
mdfind -onlyin ~/Documents 'kMDItemTextContent == "proprietary"'

# Show Spotlight index status
mdutil -sa

# Show the index store size (needs sudo)
sudo du -sh /.Spotlight-V100/
```

### Smart Folders

A Smart Folder is just a saved `mdfind` predicate stored as a `.savedSearch` file (a plist) in `~/Library/Saved Searches/`. You can create them via Finder → File → New Smart Folder, or directly:

```bash
# The .savedSearch format is a plist with a RawQuery key
cat ~/Library/Saved\ Searches/Recent\ Downloads.savedSearch \
  | plutil -convert xml1 -o - -
```

The `RawQuery` value is exactly a `mdfind` predicate string.

### ACLs — a brief note

macOS supports POSIX ACLs (`chmod +a`) layered on top of traditional `rwx` permissions. ACLs are stored as a special xattr under the name `system.posix_acl_access` but accessed via `ls -le` and `chmod +a / chmod -a`. Full coverage is in [[07-files-permissions-acls-flags]]. For Spotlight purposes, note that `mdfind` and `mdls` results respect ACLs — you can only get results for files your process has read permission on.

---

## Labs

### Lab 1 — Anatomy of a quarantine event

> ⚠️ **ADVANCED / DESTRUCTIVE:** This lab removes the quarantine xattr from a test file. Back up the file first. Rollback: you cannot re-add an authentic quarantine xattr with the original UUID (you'd have to re-download the file), but the file itself is unaffected.

```bash
# Download a test file from the internet using curl with quarantine (Safari behavior)
# The -L flag follows redirects; curl itself doesn't set quarantine
# Use Safari or Firefox to download something, or:
curl -L -o /tmp/testfile.zip https://github.com/nicowillis/xq/archive/refs/heads/main.zip

# If downloaded via browser, check quarantine
xattr -l ~/Downloads/main.zip

# Decode the quarantine string manually
QVAL=$(xattr -p com.apple.quarantine ~/Downloads/main.zip)
echo "Raw: $QVAL"
echo "Fields:"
echo "$QVAL" | tr ';' '\n' | while read -r f; do echo "  $f"; done
# Field 2 is hex epoch — decode it:
HEXTS=$(echo "$QVAL" | cut -d';' -f2)
DECTS=$((16#$HEXTS))
date -r "$DECTS"

# Look up this event in the quarantine DB
sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
  "SELECT datetime(LSQuarantineTimeStamp+978307200,'unixepoch','localtime') AS when_,
          LSQuarantineAgentName AS agent,
          LSQuarantineDataURLString AS url,
          LSQuarantineOriginURLString AS referrer
   FROM LSQuarantineEvent
   ORDER BY LSQuarantineTimeStamp DESC LIMIT 5;"

# Strip quarantine from the test file
xattr -d com.apple.quarantine ~/Downloads/main.zip

# Verify it's gone
xattr ~/Downloads/main.zip
```

### Lab 2 — mdfind for forensic artifact hunting

```bash
# List all files on the system that have been downloaded from the internet
# (have a kMDItemWhereFroms attribute) in the past 90 days
mdfind 'kMDItemWhereFroms != "" && kMDItemDownloadedDate >= $time.now(-7776000)'

# Find all screenshots (macOS sets kMDItemIsScreenCapture=1 automatically)
mdfind 'kMDItemIsScreenCapture == 1' | head -20

# Find all files where the creating app was not your usual suite
mdfind 'kMDItemCreator != "" && kMDItemCreator != "Preview" && kMDItemCreator != "Microsoft Word"' \
  -onlyin ~/Documents | head -20

# Count indexed files by content type
for uti in com.adobe.pdf public.jpeg public.mp4 public.plain-text; do
  COUNT=$(mdfind -count "kMDItemContentType == '$uti'")
  echo "$uti: $COUNT"
done
```

### Lab 3 — Explore .DS_Store on a real directory

```bash
# Check if a .DS_Store exists in your home folder
ls -la ~/

# Use strings to quick-dump directory entries recorded in it
strings ~/.DS_Store | sort -u | head -40

# Use Python (if the ds_store package is installed: pip3 install ds_store)
python3 - <<'EOF'
import ds_store
with ds_store.DSStore.open(os.path.expanduser('~/.DS_Store'), 'r') as d:
    for entry in d:
        print(entry)
EOF

# Find all .DS_Store files on an external drive
find /Volumes/MyDrive -name ".DS_Store" 2>/dev/null
```

### Lab 4 — Rebuild the Spotlight index and observe the process

> ⚠️ **ADVANCED:** This erases and rebuilds the Spotlight index for `/`. Search quality degrades during the rebuild (15–60 min on a full drive). Rollback: automatic — wait for rebuild to complete.

```bash
# Take a size baseline
sudo du -sh /.Spotlight-V100/

# Erase and rebuild
sudo mdutil -E /

# Watch the mds process tree as it rebuilds
watch -n2 'ps aux | grep -E "mds|mdworker" | grep -v grep'

# In a second terminal: watch indexing activity in real time
mdfind -live 'kMDItemContentType == "public.jpeg"'
# (This prints matching files as they get indexed — hit Ctrl-C to stop)

# After rebuild, verify
mdutil -s /
sudo du -sh /.Spotlight-V100/
```

---

## Pitfalls & gotchas

**`mdls` returns `(null)` for a file that definitely exists.** Either the file hasn't been indexed yet, is in an excluded path (check `mdutil -s /`), is on a volume with indexing disabled, or its UTI has no registered importer. Run `mdimport -t -d1 /path/to/file` to force-index it and check for importer errors.

**Copying files strips xattrs by default.** `cp` without flags drops xattrs. Use `cp -p` (preserve) or `ditto --noextattr` is the OPPOSITE — use `ditto` alone (without `--noextattr`) to preserve them. `rsync -aX` preserves xattrs on the same system; `-aX` is not sufficient over the network to a non-macOS server.

**The quarantine dialog fires on first launch, not on download.** Gatekeeper checks quarantine at open time. If you `xattr -d com.apple.quarantine` before opening, no dialog. After opening once and accepting, macOS sets the `0x0100` bit in the flags field and won't prompt again — it doesn't remove the xattr.

**`mdfind` won't search `.Spotlight-V100`-excluded paths.** The Spotlight Privacy exclusion list silently causes `mdfind` to return zero results for those paths. A forensics gotcha: if the user excluded `~/Desktop` from Spotlight, your `mdfind` queries over that directory will silently return nothing even if files match.

**Smart Folders don't search all volumes.** By default, Finder's Smart Folder search scope is "This Mac" but actually searches only volumes that have Spotlight enabled. Volumes with indexing disabled are skipped.

**`._` files are not junk on the target filesystem.** Calling `dot_clean` or deleting `._` files on a drive that macOS is still using will destroy resource forks and xattrs for those files. Only clean them when moving a drive to a non-macOS environment.

**`kMDItemTextContent` is not returned by `mdls`.** It's intentionally suppressed. Use `mdfind 'kMDItemTextContent == "term"'` to search it; you cannot read the raw body text back out via command-line tools.

**Spotlight respects SSV on macOS 11+.** The Signed System Volume is read-only and sealed. Spotlight indexes the Data volume (where your files actually live) but cannot index the System volume content because it's already known at OS build time. `mdutil -s /System/Volumes/Data` is the relevant volume for boot-volume indexing status.

---

## Key takeaways

1. **Spotlight is a daemon pipeline** — `mds` (supervisor) → `mdworker_shared` (extractor) → `.mdimporter` plugin → `mds_stores` (writer) → `.Spotlight-V100` (per-volume B-tree index).
2. **`mdfind` is your semantic `find`** — query `kMDItem*` attributes, full-text, dates, and file types with boolean predicates. `mdls` shows what Spotlight knows about a file. `mdutil` manages the index itself.
3. **Extended attributes are per-file key-value stores** at the filesystem layer — not metadata fields, not database entries, bytes in the inode record.
4. **`com.apple.quarantine`** is the most forensically significant xattr: it records what app downloaded a file, when, and carries the UUID cross-referenceable to the `QuarantineEventsV2` SQLite database — which persists after the file is deleted.
5. **`com.apple.metadata:kMDItemWhereFroms`** carries the exact download URL and referrer as a binary plist array — readable via `mdls` or `xattr | plutil`.
6. **AppleDouble `._` files** appear on non-native volumes (FAT32, SMB) and survive file deletion, leaking filenames, metadata, and sometimes quarantine data.
7. **`.DS_Store`** records what files Finder has seen in a directory — a forensic artifact for directory enumeration and deleted-file discovery.
8. **The `.Spotlight-V100` store** preserves metadata for deleted files until the next full re-index — acquire it in any macOS forensic image.

---

## Terms introduced

| Term | Definition |
|---|---|
| `mds` | Metadata Server — the Spotlight supervisor daemon |
| `mdworker_shared` | Per-file metadata extraction worker process |
| `mds_stores` | Spotlight index write daemon |
| `mediaanalysisd` | ML-based OCR/image/text analysis daemon (feeds Spotlight) |
| `.mdimporter` | Plugin bundle that extracts `kMDItem*` attributes from a specific file type |
| `.Spotlight-V100` | Per-volume hidden directory containing the Spotlight B-tree index |
| `kMDItem*` | Namespace prefix for Spotlight metadata attribute keys |
| `mdfind` | CLI tool to query the Spotlight index |
| `mdls` | CLI tool to list Spotlight attributes for a specific file |
| `mdutil` | CLI tool to manage Spotlight indexing on a volume |
| `mdimport` | CLI tool to list importers and force-index individual files |
| xattr | Extended attribute — arbitrary key-value metadata attached to a file at the filesystem level |
| `com.apple.quarantine` | Xattr set on downloaded files; carries timestamp, downloading app, and event UUID |
| `com.apple.metadata:kMDItemWhereFroms` | Xattr storing download URL and referrer as binary plist |
| `com.apple.FinderInfo` | 32-byte xattr carrying HFS+ type/creator codes and Finder flags |
| `com.apple.ResourceFork` | Xattr carrying legacy Mac OS resource fork data |
| AppleDouble | Split-file format (`._filename`) used to carry Mac metadata on non-native filesystems |
| `QuarantineEventsV2` | SQLite database at `~/Library/Preferences/` logging all quarantine events |
| `.DS_Store` | Finder-created binary file storing folder view state and observed filenames |
| Resource fork | Classic Mac OS per-file structured binary store; now an xattr on APFS/HFS+ |
| Smart Folder | A `.savedSearch` plist containing a saved `mdfind` predicate |

---

## Further reading

- **Apple Platform Security Guide** — "Gatekeeper and runtime protection" section, for the quarantine enforcement path: [https://support.apple.com/guide/security/](https://support.apple.com/guide/security/)
- **Howard Oakley — Eclectic Light Company:** ["A deeper dive into Spotlight indexing and local search"](https://eclecticlight.co/2025/08/04/a-deeper-dive-into-spotlight-indexing-and-local-search/) and ["A deeper dive into Spotlight indexes"](https://eclecticlight.co/2025/07/30/a-deeper-dive-into-spotlight-indexes/) — the most thorough public analysis of the current Spotlight pipeline
- **Apple Developer: Core Spotlight** — `NSMetadataQuery` and the `kMDItem*` attribute reference: [https://developer.apple.com/documentation/corespotlight](https://developer.apple.com/documentation/corespotlight)
- **dfir.ch: macOS Extended Attributes case study** — forensic walkthrough of quarantine and `kMDItemWhereFroms`: [https://www.dfir.ch/posts/macos_extended_attributes/](https://www.dfir.ch/posts/macos_extended_attributes/)
- **xattribs (GitHub)** — tool for bulk forensic extraction of xattrs including from QuarantineEventsV2: [https://github.com/kieczkowska/xattribs](https://github.com/kieczkowska/xattribs)
- **JSAC 2022: Introduction to macOS Forensics** — open-source forensic workflow including Spotlight, quarantine DB, .DS_Store: [https://jsac.jpcert.or.jp/archive/2022/pdf/JSAC2022_workshop_macOS-forensic_en.pdf](https://jsac.jpcert.or.jp/archive/2022/pdf/JSAC2022_workshop_macOS-forensic_en.pdf)
- Related lessons: [[03-apfs-deep-dive]] · [[04-filesystem-layout-and-domains]] · [[08-security-architecture]] · [[07-files-permissions-acls-flags]] · [[03-forensic-artifacts]]
