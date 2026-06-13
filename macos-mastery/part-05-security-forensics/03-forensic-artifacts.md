---
title: Forensic Artifacts on macOS
part: P05 Security/Forensics
est_time: 90 min read + 60 min labs
prerequisites: [01-boot-process, 02-apfs-deep-dive]
tags: [macos, forensics, dfir, artifacts, sqlite, unified-logs, apfs, knowledgec, fseventsd]
---

# Forensic Artifacts on macOS

> **In one sentence:** macOS is a forensic goldmine — a dozen overlapping artifact stores (SQLite databases, binary plists, compressed binary logs, extended attributes, APFS snapshots) provide redundant, cross-corroborating evidence that together reconstruct user activity, application execution, file movement, and authentication events with sub-second temporal precision.

---

> ⚠️ **AUTHORIZED USE ONLY.** Everything in this lesson is written for lawfully authorized examination — incident response on your own machine, authorized corporate forensics, or criminal investigation under proper legal authority. Reading another person's forensic artifacts without authorization is a federal crime (CFAA) and a state crime in nearly every US jurisdiction. Maintain chain of custody: image before you examine, work on copies, log every command.

---

## Why this matters

Windows investigators arrive on macOS expecting Registry hives, Event Log EVTXs, and Prefetch files. None of those exist. macOS uses a completely different artifact ecosystem: SQLite databases scattered through `~/Library`, APFS-native extended attributes, a structured binary log format that replaced syslog wholesale in macOS 10.12, and a "knowledge" database that is effectively Apple's own behavioral analytics engine running on every Mac. A forensicator who doesn't know where to look will miss an enormous amount of evidence — or worse, will unknowingly alter it by launching the wrong tool. This lesson is a practitioner map. Every artifact here: where it lives on disk, what format it uses, what questions it can answer, and how to read it without destroying its evidentiary value.

---

## Concepts

### The Volatility Hierarchy

Before touching anything, internalize this ordering from most to least volatile:

```
RAM / page file         → lost on shutdown; requires live-memory acquisition
Kernel network state    → active connections, ARP cache, routing table
Processes + open files  → pgrep, lsof, netstat snapshots
Unified Logs (live)     → ~28-30 day rolling window, oldest entries overwritten first
User activity databases → knowledgeC.db, QuarantineEventsV2 (persist until purged)
APFS snapshots / TM     → point-in-time filesystem images (hours to months back)
Filesystem artifacts    → .DS_Store, xattrs, FSEvents (persist until space pressure)
Application state       → Saved State, QuickLook thumbnails (persist across reboots)
Persistent config       → plists, Keychain, SQLite stores (survive erasure-level events)
```

For a dead-box examination, you're working at the bottom; for live IR, you care about the top. The artifacts below are roughly ordered: system-level logs → user behavior → file-level metadata → application data → historical state.

> 🪟 **Windows contrast:** Windows Event Logs (EVTX) have a roughly equivalent role to macOS Unified Logs, but `.tracev3` files are binary, cannot be opened in a text editor, and require Apple's own `log` command or third-party parsers to decode. There is no direct equivalent to the Registry; macOS uses a filesystem of individual property list files instead.

---

### 1. Unified Logs — `/private/var/db/diagnostics/` + `/private/var/db/uuidtext/`

**Format:** Proprietary binary `.tracev3` (chunked, compressed, structured). Files are named `logdata.Persistent.YYYYMMDDTHHMMSS.tracev3` plus high-frequency `logdata.Signpost.*.tracev3` and `logdata.Special.*.tracev3` variants.

**Mechanism:** Since macOS 10.12 Sierra, every subsystem — the kernel, daemons, apps, frameworks — logs via `os_log()` to a kernel buffer drained by `logd`. `logd` writes the tracev3 files. The UUID-keyed strings in `/var/db/uuidtext/` are log *format strings* compiled into the binary; `logd` stores only the UUIDs on disk to save space, rehydrating them at display time by looking up the binary that emitted them. On a live system, `/var/log/` still exists (for legacy `syslog` compatibility) but contains a tiny fraction of what the Unified Log captures.

**Retention:** ~28–30 days of rolling storage, typically 500 MB–1 GB compressed. Persistence logs survive reboot; in-memory logs do not.

**What it proves:**
- Application launches and crashes (subsystem `com.apple.launchd`, category `perf`)
- Authentication and sudo usage (subsystem `com.apple.authorization`)
- Network connections initiated by each process (subsystem `com.apple.networkd`)
- USB/Thunderbolt attachment events (subsystem `com.apple.iokit`)
- Security daemon activity: XProtect, Gatekeeper, TCC decisions
- Login/logout, screen lock/unlock, screensaver activation
- Time changes, timezone changes (which can indicate anti-forensics)

**Reading without altering:**
```bash
# On a live system — does NOT write to the log store
log show --last 7d --predicate 'process == "sudo"' --style json > sudo_events.json

# Filter for authentication events
log show --last 30d \
  --predicate 'subsystem == "com.apple.authorization" OR subsystem == "com.apple.securityd"' \
  --info --style syslog | head -200

# USB device attachment
log show --last 30d \
  --predicate 'subsystem == "com.apple.iokit" AND category == "IOUSBHostFamily"' \
  --style json

# Boot and shutdown events (good for timeline anchoring)
log show --predicate 'eventMessage CONTAINS "Wake reason" OR eventMessage CONTAINS "Shutdown cause"' \
  --last 30d --style syslog
```

For offline analysis (mounted image or exported `.logarchive`):
```bash
# Export the entire log store to a portable archive
log collect --output /path/to/output.logarchive --last 30d

# Parse on any macOS host
log show --archive /path/to/output.logarchive \
  --predicate 'process == "loginwindow"' --style json
```

**mac_apt plugin:** `UNIFIEDLOGEXPORT` — exports all tracev3 to a browsable SQLite database.

> 🔬 **Forensics note:** The `.tracev3` format includes a `bootUUID` field linking each log entry to a specific boot session. If a suspect claims "I wasn't using the Mac at that time," boot session correlation via `log show --predicate 'eventMessage CONTAINS "Previous shutdown cause"'` can establish whether the machine was even on.

---

### 2. KnowledgeC.db — `~/Library/Application Support/Knowledge/knowledgeC.db`

**Format:** SQLite 3. The workhorse table is `ZOBJECT`; supporting tables include `ZSTRUCTUREDMETADATA` and `ZSOURCE`.

**Mechanism:** The `knowledged` daemon (part of Apple's on-device intelligence / Screen Time / Siri Suggestions stack) continuously records what the user is doing and maps it to time intervals. Every row in `ZOBJECT` has a `ZSTREAMNAME` (the artifact type) and start/end timestamps in Apple Mac Absolute Time (seconds since 2001-01-01 00:00:00 UTC).

**Key `ZSTREAMNAME` values:**

| Stream | What it records |
|---|---|
| `/app/inFocus` | Foreground application + bundle ID, start+end time |
| `/app/usage` | Broader usage intervals, including background activity |
| `/app/install` | App installation events |
| `/device/locked` | Device lock and unlock transitions |
| `/display/isBacklit` | Screen on/off — wakes, sleeps |
| `/media/playing` | Audio/video playback (app, title, artist, URL) |
| `/safari/webUsage` | Browser domains visited |
| `/device/phoneCall` | Call history (on Macs with Continuity) |
| `/now_playing/nowPlaying` | What was playing via Now Playing widget |
| `/com.apple.focus/focus_mode` | Focus mode (Do Not Disturb, Work, etc.) transitions |

**Reading without altering:**
```bash
# CRITICAL: copy the database before querying — SQLite opens write locks even for SELECT
cp ~/Library/Application\ Support/Knowledge/knowledgeC.db /tmp/knowledgeC_copy.db

sqlite3 /tmp/knowledgeC_copy.db "
SELECT
  ZOBJECT.ZSTREAMNAME,
  ZOBJECT.ZVALUESTRING,
  datetime(ZOBJECT.ZSTARTDATE + 978307200, 'unixepoch', 'localtime') AS start,
  datetime(ZOBJECT.ZENDDATE   + 978307200, 'unixepoch', 'localtime') AS end,
  ZOBJECT.ZSECONDSFROMGMT / 3600.0 AS tz_offset_h
FROM ZOBJECT
WHERE ZSTREAMNAME = '/app/inFocus'
ORDER BY ZSTARTDATE DESC
LIMIT 50;
"
```

The magic constant `978307200` converts Apple Mac Absolute Time (epoch 2001-01-01) to Unix epoch (1970-01-01).

**APOLLO** (Sarah Edwards' tool — `github.com/mac4n6/APOLLO`) automates extraction of all streams into a unified timeline with human-readable output:
```bash
python3 apollo.py -o timeline.csv \
  -d /tmp/knowledgeC_copy.db \
  -m modules/  # uses all bundled module .txt query files
```

> 🔬 **Forensics note:** `/device/locked` transitions let you establish whether the machine was physically attended at a specific time. Combined with `/app/inFocus` and `/display/isBacklit`, you can build a minute-by-minute presence timeline. This has been used to rebut "I was away from my desk" defenses.

> 🪟 **Windows contrast:** The closest Windows equivalent is the UserAssist Registry key (MRU counts + last-run timestamps) and the Windows Timeline ActivityCache.db. knowledgeC.db is far richer — it captures duration, not just last-run, for every foreground app.

---

### 3. Quarantine + `where_from` XAttrs + LSQuarantineEventsV2

**Mechanism:** When any quarantine-aware app (Safari, Mail, Messages, Chrome, curl via `NSURLDownload`) writes a file to disk, the kernel's Security framework automatically attaches two extended attributes via `setxattr(2)`:

1. `com.apple.quarantine` — a semicolon-delimited string: flags;timestamp(hex epoch);originating-app-bundle;UUID.  
   Example: `0081;64f1a3c2;com.apple.Safari;AB12CD34-...`

2. `com.apple.metadata:kMDItemWhereFroms` — a binary plist array of URLs: typically `[direct_download_url, page_url_that_linked_to_it]`.

**Database:** `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` (SQLite). This persists records even after the xattr is stripped from the file or the file is deleted.

```bash
# Read xattrs on a downloaded file
xattr -l ~/Downloads/SomeTool.dmg
# com.apple.quarantine: 0081;64f1a3c2;com.apple.Safari;UUID
# com.apple.metadata:kMDItemWhereFroms: <binary plist>

# Decode the where-from plist inline
xattr -p com.apple.metadata:kMDItemWhereFroms ~/Downloads/SomeTool.dmg \
  | xxd -r -p | plutil -convert xml1 -o - -

# Query the quarantine database (copy first)
cp ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 /tmp/qe.db
sqlite3 /tmp/qe.db "
SELECT
  datetime(LSQuarantineTimeStamp + 978307200, 'unixepoch', 'localtime') AS download_time,
  LSQuarantineAgentBundleIdentifier AS app,
  LSQuarantineDataURLString AS url,
  LSQuarantineOriginURLString AS referrer,
  LSQuarantineSenderName
FROM LSQuarantineEvent
ORDER BY LSQuarantineTimeStamp DESC
LIMIT 50;
"
```

> 🔬 **Forensics note:** The QuarantineEventsV2 database is persistent — it survives file deletion. A user can `rm ~/Downloads/malware.dmg` and strip the xattr, but the download event remains in the database. Rows are only pruned after 90 days by default (`com.apple.LaunchServices` preference `LSQuarantineMaxEventCount`). This means you can prove a file was downloaded even if the file itself is gone.

> 🔬 **Forensics note:** The `com.apple.quarantine` flag is also the gating mechanism for Gatekeeper. Anti-forensic tools and malware sometimes strip it deliberately via `xattr -d com.apple.quarantine`. Absence of the flag on an internet-sourced binary — or a mismatched timestamp — is itself an indicator.

---

### 4. FSEvents — `/.fseventsd/` (or `/System/Volumes/Data/.fseventsd/` on sealed volumes)

**Format:** Binary, gzip-compressed event record files. Each file contains a sequence of variable-length records encoding: filesystem path (null-terminated UTF-8), event flags (32-bit bitmask: `CREATE`, `REMOVE`, `RENAME`, `MODIFY`, `CHOWN`, `XATTR`, `IS_DIR`, `IS_SYMLINK`, etc.), and a monotonically increasing event ID.

**Mechanism:** The `fseventsd` daemon subscribes to the kernel's `FSEvents` facility (`/dev/fsevents`). It drains the kernel event queue and batches records into files under `/.fseventsd/`. Files are rotated when they reach ~128 KB. There is no explicit time stamp per event — wall-clock time must be inferred from Time Machine snapshot correlation or log cross-reference. The event IDs are monotone and can be correlated with APFS snapshot creation events (APFS records the FSEvents ID at snapshot time).

**Forensic value:** FSEvents logs every path touched on the volume — files created, deleted, renamed, moved, and files whose metadata was changed — including operations that completed and left no other artifact (e.g., a file written and then deleted in the same session). This makes it valuable for anti-forensics detection: evidence of "cleaned" paths appears as REMOVE events on paths the system never legitimately needed to touch.

```bash
# FSEventsParser by G-C Partners (Python)
pip install fseventparser   # or clone github.com/dlcowen/FSEventsParser
python fseventsparser.py -f /System/Volumes/Data/.fseventsd/ -o /tmp/fsevents_out/

# mac_apt plugin
python mac_apt.py -o /tmp/mac_apt_output/ FSEVENTS
```

> 🔬 **Forensics note:** FSEvents records are per-volume. External drives have their own `.fseventsd/` at their root. Plugging a USB drive in and copying files records those events in the drive's own `.fseventsd/`, not the Mac's — which means the drive itself carries evidence of what was done to it, regardless of what the Mac's logs show.

---

### 5. Spotlight Metadata — `/.Spotlight-V100/`

**Format:** A proprietary inverted index database (not directly SQLite-readable). Stores metadata extracted from every indexed file: `kMDItem*` attributes (file name, content type, author, creation date, GPS coordinates, camera model, email recipients, etc.).

**Forensic value:** Spotlight indexes files even if they are later deleted, until the index is rebuilt. More importantly, for dead-box analysis `mdfind` is unavailable, but the index artifacts under `.Spotlight-V100/Store-V2/` can be parsed by tools like `mac_apt` (`SPOTLIGHT` and `SPOTLIGHTSHORTCUTS` plugins) to reconstruct a list of files that *existed* on the volume, even if they no longer do.

The `store.db` inside `Store-V2/` is a CoreData-style persistent store; direct SQLite access is unreliable. Use `mdls` on live files for per-file metadata:

```bash
# Rich metadata for a single file
mdls ~/Downloads/SomeTool.dmg

# Find all files downloaded from the internet
mdfind 'kMDItemWhereFroms == "*"' -onlyin ~/Downloads

# Find all images with GPS data
mdfind 'kMDItemLatitude > 0' -onlyin ~/Pictures
```

---

### 6. Finder `.DS_Store` Files

**Format:** Binary, undocumented Apple proprietary format (B-tree structure). Parseable with `python-dsstore`, `dsstore` Go library, or mac_apt.

**What they contain:** Per-file Finder view state: icon positions, list-column widths, window backgrounds, but also — critically — **the names of files and folders that existed in that directory when Finder last opened it**, including files that have since been deleted.

```bash
# Install parser
pip install dsstore   # or: brew install ds_store_parser (community)

python3 -c "
from ds_store import DSStore
with DSStore.open('/path/to/.DS_Store') as ds:
    for record in ds:
        print(record.filename, record.code, record.value)
"
```

> 🔬 **Forensics note:** `.DS_Store` files exist on every volume Finder has ever visited, including USB drives and network shares. A `.DS_Store` left on a USB drive by the suspect's Mac proves that Mac's Finder opened that folder, and lists what files Finder saw at that time.

---

### 7. Recent Items / Shared File Lists — `~/Library/Application Support/com.apple.sharedfilelist/`

**Format:** Binary plists (`.sfl2` files, parseable with `plutil -convert xml1`). Since macOS 10.13 these replaced the older `com.apple.recentitems.plist`.

**Key files:**

| File | Contents |
|---|---|
| `com.apple.LSSharedFileList.RecentApplications.sfl2` | Recent apps |
| `com.apple.LSSharedFileList.RecentDocuments.sfl2` | Recent documents |
| `com.apple.LSSharedFileList.RecentServers.sfl2` | Recently connected servers |
| `com.apple.LSSharedFileList.FavoriteItems.sfl2` | Sidebar favorites |
| `com.apple.LSSharedFileList.RecentHosts.sfl2` | Recent Screen Sharing / AFP hosts |

```bash
# Convert and inspect
plutil -convert xml1 -o - \
  ~/Library/Application\ Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl2 \
  | grep -A3 '<key>LSDisplayName</key>'
```

Each entry encodes a Bookmark (serialized NSURL) that resolves to the original path, plus creation date metadata. Even if the file is deleted, the bookmark record — and its embedded metadata — persists in the `.sfl2` until the list is manually cleared.

---

### 8. Browser Artifacts

#### Safari

| Artifact | Path | Format |
|---|---|---|
| History | `~/Library/Safari/History.db` | SQLite |
| Downloads | `~/Library/Safari/Downloads.plist` | Binary plist |
| Top Sites | `~/Library/Safari/TopSites.plist` | Binary plist |
| Web cache | `~/Library/Caches/com.apple.Safari/Cache.db` | SQLite (WebKit cache format) |
| Cookies | `~/Library/Cookies/Cookies.binarycookies` | Proprietary binary |

```bash
cp ~/Library/Safari/History.db /tmp/safari_history.db
sqlite3 /tmp/safari_history.db "
SELECT
  datetime(visit_time + 978307200, 'unixepoch', 'localtime') AS visit_time,
  url, title, visit_count
FROM history_visits
JOIN history_items ON history_visits.history_item = history_items.id
ORDER BY visit_time DESC
LIMIT 100;
"
```

Cookie parsing requires a dedicated tool (e.g., BinaryCookieReader or mac_apt's `COOKIES` plugin) — the `.binarycookies` format is not SQLite.

#### Chrome / Chromium-based Browsers

```
~/Library/Application Support/Google/Chrome/Default/History          # SQLite
~/Library/Application Support/Google/Chrome/Default/Cookies          # SQLite (encrypted)
~/Library/Application Support/Google/Chrome/Default/Login Data       # SQLite (encrypted)
~/Library/Application Support/Google/Chrome/Default/Bookmarks        # JSON
```

Chrome history SQLite schema is broadly cross-platform; the `urls` and `visits` tables work the same as on Windows.

---

### 9. Messages — `~/Library/Messages/chat.db`

**Format:** SQLite. The `message` table links to `handle` (participants) and `attachment` (files sent/received).

```bash
cp ~/Library/Messages/chat.db /tmp/chat_copy.db
sqlite3 /tmp/chat_copy.db "
SELECT
  datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') AS msg_time,
  handle.id AS sender,
  message.text,
  message.is_from_me
FROM message
LEFT JOIN handle ON message.handle_id = handle.ROWID
ORDER BY message.date DESC
LIMIT 50;
"
```

Note the date field: pre-macOS 13, timestamps are Apple Absolute Time (add 978307200). From macOS 13+, they are nanoseconds since the Apple epoch, so divide by 1e9 first, then add the epoch offset. The query above handles both cases by dividing by 1,000,000,000.

Attachments are stored in `~/Library/Messages/Attachments/` in a path-sharded directory tree. The `attachment` table in chat.db maps message rows to relative paths there.

> 🔬 **Forensics note:** iMessage uses end-to-end encryption in transit, but chat.db on the endpoint is stored unencrypted (protected only by filesystem permissions and FileVault). This makes local acquisition far simpler than network interception.

---

### 10. Notes — `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`

**Format:** SQLite with binary-blob columns (ZDATA = gzipped protobuf representing rich text). Attachments live alongside the database. Not trivially human-readable — use mac_apt's `NOTES` plugin or specialized Notes export tools.

The database contains note title, creation/modification timestamps, account source (iCloud vs. local), and folder membership. Deleted notes linger in `ZICCLOUDSYNCINGOBJECT` rows flagged with `ZMARKEDFORDELETION = 1` until a cloud sync purge.

---

### 11. Mail — `~/Library/Mail/`

**Format:** Each account has a UUID-named subdirectory containing `.mbox`-style folder trees. Individual messages are stored as plain `.eml` files (MIME RFC 2822). Attachments are stored alongside. The `Envelope Index` at `~/Library/Mail/V10/MailData/Envelope Index` is an SQLite database indexing all messages.

```bash
sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index "
SELECT
  datetime(date_sent, 'unixepoch', 'localtime') AS sent,
  sender, subject
FROM messages
ORDER BY date_sent DESC
LIMIT 30;
"
```

> 🔬 **Forensics note:** Even after a message is "deleted" in Mail.app, it moves to Trash and only disappears from the `Envelope Index` after the Trash is emptied. MBOX files may persist in `~/Library/Mail/` trash folders longer than expected. Time Machine snapshots often preserve deleted mail.

---

### 12. Photos Library — `~/Pictures/Photos Library.photoslibrary/`

**Format:** A macOS package (directory masquerading as a single file). Inside: `database/Photos.sqlite` (SQLite, the core catalog), `originals/` (original media files), `resources/` (derived/edited versions). The SQLite schema is complex — mac_apt's `PHOTOS` plugin or the `osxphotos` CLI provide cleaner access.

```bash
# osxphotos (brew install osxphotos)
osxphotos info --json | jq '.[0:5]'           # first 5 photos with metadata
osxphotos query --json --from-date 2024-01-01 # filter by date
```

Photos.sqlite contains: original filename, GPS coordinates, faces/people recognition data (person names linked to face clusters), album membership, keywords, shared album membership, and edit history. The `ZGENERICASSET` table is the primary asset table.

---

### 13. APFS Snapshots + Time Machine as Historical State

APFS snapshots are copy-on-write frozen filesystem states. macOS creates local snapshots automatically (`tmutil listlocalsnapshots /`) as a safety net before major updates and as part of Time Machine backup.

```bash
# List local APFS snapshots
tmutil listlocalsnapshots /
# com.apple.TimeMachine.2024-11-15-103022.local

# Mount a snapshot read-only (safe — copy-on-write; original is unaffected)
mkdir /tmp/snap_mount
mount_apfs -s com.apple.TimeMachine.2024-11-15-103022.local / /tmp/snap_mount

# Now browse it — this is what the filesystem looked like at that moment
ls /tmp/snap_mount/Users/
diff /tmp/snap_mount/Users/alice/Desktop/ ~/Desktop/

# Unmount when done
umount /tmp/snap_mount
```

For forensics: snapshots are a legal-hold goldmine. A snapshot from before a suspected deletion preserves the file in its original state. APFS snapshots also record the FSEvents event ID at creation time, allowing you to correlate FSEvents entries to "before this snapshot" vs. "after."

> ⚠️ **ADVANCED:** Snapshots can be deleted by `tmutil deletelocalsnapshots`. Document all existing snapshots before any analysis, and image them before touching the original volume.

> 🪟 **Windows contrast:** Windows Volume Shadow Copies (VSS) are the equivalent. APFS snapshots are more deeply integrated — they are part of the filesystem format itself, not a separate service — and more space-efficient (truly copy-on-write at the block level, not pre-allocated shadow space).

---

### 14. Login and Authentication Events

```bash
# Recent sudo usage
log show --predicate 'process == "sudo"' --last 30d --style syslog

# SSH logins (legacy log + unified)
log show --predicate 'process == "sshd"' --last 30d --style syslog

# Console login / logout (loginwindow)
log show --predicate 'subsystem == "com.apple.loginwindow"' --last 30d \
  --style json | jq '.[] | select(.eventMessage | test("login|logout|authen"))'

# utmpx-style wtmp equivalent — last logins
last                     # reads /var/log/wtmp (binary utmpx format)
lastb                    # failed login attempts (if enabled)

# Authentication policy decisions
log show --predicate 'subsystem == "com.apple.authorization"' --last 7d \
  --style syslog | grep -i "denied\|granted"
```

The `utmpx` binary log at `/var/run/utmpx` (and `/var/log/wtmp`) is the macOS equivalent of the Windows Security event log login entries. mac_apt's `UTMPX` plugin extracts these to CSV.

---

### 15. Keychain — `~/Library/Keychains/` + `/Library/Keychains/`

**Format:** SQLite (since macOS 10.9, the Keychain database is `keychain-2.db` inside a UUID-named directory). Encrypted with AES-256-CBC; keys derived from the user's login password (for the login keychain) and protected by the Secure Enclave on Apple Silicon for the system keychain.

**What it contains:** Saved passwords (web, WiFi, email), certificates and private keys, application credentials, secure notes. The metadata (item labels, creation/modification dates, application access lists) is visible without decryption. The secrets themselves require the user's login password.

```bash
# List Keychain items (no secrets) — works without unlock
security list-keychains
security dump-keychain -r ~/Library/Keychains/*/keychain-2.db

# With unlock (requires password):
security find-internet-password -s github.com -w  # returns the password
security find-generic-password -s "My WiFi" -w
```

> 🔬 **Forensics note:** Even without decryption, Keychain metadata — item labels, creation dates, access control lists showing which apps have been granted access — is forensically useful. The `kSecAttrCreationDate` on a credential may predate or postdate the account's supposed existence.

---

### 16. Bash / Zsh History

```
~/.bash_history          # bash; controlled by HISTFILE, HISTSIZE, HISTFILESIZE
~/.zsh_history           # zsh; includes timestamps if EXTENDED_HISTORY is set
~/.local/share/fish/fish_history   # fish shell (YAML-like format with timestamps)
```

Zsh with `setopt EXTENDED_HISTORY` writes entries as `: epoch:elapsed;command`. The timestamp is reliable forensic evidence when present. History is deliberately absent when commands are prefixed with a space (the leading-space trick users know to avoid logging).

```bash
# Parse zsh extended history with timestamps
python3 -c "
import re, datetime, sys
for line in open(sys.argv[1]):
    m = re.match(r'^: (\d+):(\d+);(.+)', line.strip())
    if m:
        ts = datetime.datetime.fromtimestamp(int(m.group(1)))
        print(ts, m.group(3))
" ~/.zsh_history | tail -50
```

> 🔬 **Forensics note:** History files are trivially erasable (`history -p` in zsh, `rm ~/.zsh_history`). Their *absence* on a machine used heavily by a technical user is itself an indicator of anti-forensic activity. Unified Logs can partially reconstruct shell activity through process-exec events.

---

### 17. QuickLook Thumbnail Cache — `~/Library/Caches/com.apple.QuickLook.thumbnailcache/`

**Format:** SQLite index (`index.sqlite`) + binary blob files (PNG thumbnails). The index maps file paths (with inode numbers) to thumbnail blobs.

**What it proves:** A QuickLook thumbnail is generated when Finder previews a file (Spacebar, icon view with previews on, or Cover Flow). If a user viewed an image file that has since been deleted, the thumbnail may persist in this cache, proving the file existed and was viewed.

```bash
sqlite3 ~/Library/Caches/com.apple.QuickLook.thumbnailcache/index.sqlite "
SELECT key, hit_count, last_hit_date, file_last_modified
FROM thumbnails
ORDER BY last_hit_date DESC LIMIT 20;
"
```

mac_apt's `QUICKLOOK` plugin extracts and exports the thumbnail images themselves.

---

### 18. Saved Application State — `~/Library/Saved Application State/`

**Format:** Per-app directories named `<bundle-id>.savedState/`, each containing binary plist files (window geometry, scroll positions) and optionally SQLite databases or serialized view state. The content is app-specific and varies widely.

**Forensic value:** Reveals which applications were open (and their window state) at last quit. Some apps persist document paths or recently viewed content in their saved state even if the document itself is deleted. Text editors in particular often save buffer content.

```bash
ls ~/Library/Saved\ Application\ State/
# com.apple.finder.savedState/
# com.apple.Terminal.savedState/
# org.vim.MacVim.savedState/

plutil -convert xml1 -o - \
  ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState/data.data
```

---

### 19. The `mac_apt` Toolchain — Unified Offline Parsing

`mac_apt` (github.com/ydkhatri/mac_apt, Yogesh Khatri) is a Python-based cross-platform artifact parser that can process a live system, a mounted image, or a `.dmg`/`.E01` disk image. It outputs all artifacts to SQLite databases and CSV/XLSX, allowing import into timeline tools (Timesketch, log2timeline/Plaso, Excel).

**Critical usage pattern for forensic integrity:**
```bash
# Always work from an image, never the live system
# Acquire with:  sudo dd if=/dev/disk0 of=/Volumes/ExternalDrive/suspect.dmg bs=4m
# Or with Disk Utility → image → compressed DMG

# Then parse offline:
python3 mac_apt.py -i /path/to/suspect.dmg \
  -o /path/to/output/ \
  -f SQLITE \
  QUARANTINE FSEVENTS SAFARI IMESSAGE NOTES KNOWLEDGEC \
  RECENTITEMS QUICKLOOK SAVEDSTATE UNIFIEDLOGEXPORT
```

Key plugins: `QUARANTINE`, `FSEVENTS`, `SAFARI`, `IMESSAGE`, `NOTES`, `KNOWLEDGEC`, `RECENTITEMS`, `QUICKLOOK`, `SAVEDSTATE`, `UNIFIEDLOGEXPORT`, `TCC`, `AUTOSTART`, `INSTALLHISTORY`, `WIFI`, `SPOTLIGHT`, `BLUETOOTH`.

---

## Hands-on (CLI & GUI)

### Read a Live System's Quarantine DB

```bash
cp ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 /tmp/qe_live.db
sqlite3 /tmp/qe_live.db \
  "SELECT datetime(LSQuarantineTimeStamp+978307200,'unixepoch','localtime'), \
          LSQuarantineDataURLString, LSQuarantineAgentBundleIdentifier \
   FROM LSQuarantineEvent ORDER BY 1 DESC LIMIT 20;"
```

### Extract app-focus timeline from knowledgeC.db

```bash
cp ~/Library/Application\ Support/Knowledge/knowledgeC.db /tmp/kc.db
sqlite3 /tmp/kc.db "
  SELECT ZVALUESTRING as app,
         datetime(ZSTARTDATE+978307200,'unixepoch','localtime') as start,
         datetime(ZENDDATE+978307200,'unixepoch','localtime') as end,
         CAST((ZENDDATE - ZSTARTDATE) as INTEGER) as secs
  FROM ZOBJECT WHERE ZSTREAMNAME='/app/inFocus'
  ORDER BY ZSTARTDATE DESC LIMIT 30;" | column -t -s '|'
```

### Decode `where_from` xattr

```bash
xattr -p com.apple.metadata:kMDItemWhereFroms ~/Downloads/*.dmg 2>/dev/null \
  | xxd -r -p \
  | plutil -convert xml1 -o - -
```

### Unified Log authentication timeline

```bash
log show --last 14d \
  --predicate '(process == "sudo" OR process == "sshd" OR process == "loginwindow") AND eventType == logEvent' \
  --style compact 2>/dev/null | grep -iE 'auth|login|fail|deny|granted' | tail -40
```

---

## 🧪 Labs

> ⚠️ **Labs use YOUR live system.** These are read-only queries against copies — nothing writes to system databases. The `cp` before every `sqlite3` call is mandatory. Do not skip it. Backup recommendation: take a local Time Machine snapshot before the destructive lab (`sudo tmutil snapshot`). Rollback: the snapshot is mountable read-only; nothing in these labs modifies system state.

### Lab 1: Build a presence timeline from knowledgeC.db

1. Copy `~/Library/Application Support/Knowledge/knowledgeC.db` to `/tmp/kc_lab.db`.
2. Run the `/app/inFocus` query above. Note which apps dominate your time.
3. Add a `WHERE ZSTREAMNAME='/device/locked'` query. Map lock/unlock events against the app-focus timeline. Were there gaps in app focus that correlate with lock events?
4. Run APOLLO against the copy and open the CSV in Numbers or Excel. Filter to yesterday and describe the pattern.

### Lab 2: Audit your quarantine history

1. Copy `LSQuarantineEventsV2` to `/tmp/qe_lab.db`.
2. Query all unique originating apps (`LSQuarantineAgentBundleIdentifier`) and count events per app.
3. Find the oldest record. This is the earliest download macOS has a record of on this machine.
4. Find any rows where `LSQuarantineDataURLString` is empty — these indicate downloads where the URL was not captured (e.g., copied from another source, or the app didn't pass it to the API).

### Lab 3: Read your own FSEvents log

> ⚠️ **ADVANCED / DESTRUCTIVE potential:** FSEventsParser reads from the live `.fseventsd` — it does not modify it, but parsing errors can occasionally cause the tool to terminate uncleanly. Work on a copy of the `.fseventsd` directory if possible.

1. `sudo cp -R /System/Volumes/Data/.fseventsd /tmp/fseventsd_copy`
2. Install FSEventsParser: `pip3 install fseventparser`
3. Run: `python3 -m fseventparser -f /tmp/fseventsd_copy -o /tmp/fsevents_output`
4. Open the CSV. Filter for your username in the path. Find the 10 most recently created files. Verify they match your recent work.

### Lab 4: Mount an APFS snapshot

> ⚠️ **ADVANCED:** Mounting a snapshot requires `sudo`. The snapshot is strictly read-only; you cannot accidentally modify it. Unmount cleanly with `umount /tmp/snap_mnt` when done.

```bash
# List available snapshots
tmutil listlocalsnapshots /

# Pick one, mount it
SNAP=$(tmutil listlocalsnapshots / | head -1)
mkdir -p /tmp/snap_mnt
sudo mount_apfs -s "$SNAP" / /tmp/snap_mnt

# Compare Desktop state then vs. now
diff <(ls -la /tmp/snap_mnt/Users/$USER/Desktop/) <(ls -la ~/Desktop/)

# Unmount
sudo umount /tmp/snap_mnt
```

### Lab 5: Correlate a Unified Log event with knowledgeC.db

1. Pick a specific 30-minute window yesterday.
2. Query knowledgeC.db for `/app/inFocus` in that window.
3. Run `log show --start "2024-XX-XX HH:MM:SS" --end "2024-XX-XX HH:MM:SS" --style json` for the same window.
4. Find at least one log event that corroborates what knowledgeC.db shows as the foreground app.

---

## Pitfalls & gotchas

**Never open SQLite databases on the live system without copying first.** SQLite opens write locks even on `SELECT` — WAL mode creates `-wal` and `-shm` sidecar files on first connection. Opening `chat.db` directly modifies it. Every query above copies first.

**Apple Absolute Time vs. Unix epoch vs. WebKit time.** macOS uses at least three epoch systems: Unix (1970), Apple Absolute (2001, add 978307200 to convert), and WebKit/Chrome (1601-01-01 + microseconds). Know which database uses which. KnowledgeC.db and QuarantineEventsV2 use Apple Absolute. Safari History.db uses Apple Absolute. Chrome uses WebKit. Mixing them produces timestamps 30+ years off.

**The `log` command streams from the live log store, not a snapshot.** If you run `log show` without capturing to a `.logarchive` first, you're querying a live, changing data source. Export to a `.logarchive` before analysis when chain of custody matters.

**SIP protects the system volume.** Even with root, you cannot directly read files on the sealed System volume (`/System/Volumes/Preboot`, `/System/Volumes/xarts`, etc.) from userspace. The Data volume (`/System/Volumes/Data`, mounted at `/` via firmlinks for user data) is accessible. See [[01-boot-process]] for SSV details.

**FileVault changes the acquisition workflow entirely.** All user-data artifacts above are encrypted at rest when FileVault is enabled. Acquisition of an encrypted volume without the recovery key or decrypted image is not forensically productive. On Apple Silicon, the Secure Enclave holds the volume encryption keys — there is no cold-boot attack. See the Apple Platform Security guide for details on the key derivation hierarchy.

**`.DS_Store` files update on Finder focus, not just on view changes.** Simply browsing to a directory in Finder updates its `.DS_Store`. This can contaminate evidence — always image before browsing in Finder.

**QuarantineEventsV2 records are prunable.** Users can clear the quarantine database via `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 "DELETE FROM LSQuarantineEvent;"`. Absence of records for a time period when the machine was clearly in use is an indicator.

---

## Key takeaways

1. macOS has no Registry and no EVTX, but has a richer artifact landscape than most investigators expect — layered, cross-corroborating, and often redundant.
2. **Copy before query.** SQLite is the format of choice for most macOS user-data artifacts; every database query must operate on a forensic copy.
3. **Unified Logs are your most comprehensive system timeline** but have a ~30-day window. Collect them immediately in IR; they are the macOS equivalent of Windows Security event logs plus application logs plus kernel logs, combined.
4. **KnowledgeC.db is the behavioral analytics engine** Apple runs on every Mac. It proves app focus duration, device lock state, and display state — often enough to reconstruct minute-by-minute user presence.
5. **The Quarantine database outlives the file.** Downloads are recorded even after deletion; the database proves a file existed and was downloaded even when the file is gone.
6. **FSEvents is the filesystem history**; APFS snapshots provide point-in-time filesystem images. Together they answer "what existed when?"
7. **mac_apt and APOLLO** are the standard community tools for batch extraction; know their plugin lists and run them against images, never live systems.
8. **Anti-forensic indicators** to watch: stripped quarantine xattrs, missing zsh history on a power user's machine, QuarantineEventsV2 gaps, and REMOVE events in FSEvents on paths inconsistent with normal use.

---

## Terms introduced

| Term | Definition |
|---|---|
| `.tracev3` | Binary compressed log format used by macOS Unified Logging since 10.12 |
| `logd` | The daemon that drains the kernel log buffer and writes `.tracev3` files |
| Apple Mac Absolute Time | Timestamp epoch of 2001-01-01 00:00:00 UTC; used in most Apple SQLite stores |
| KnowledgeC.db | SQLite database recording app usage, device state, and media playback; maintained by `knowledged` |
| `ZOBJECT` | Primary table in KnowledgeC.db; each row is a timed behavioral event with a stream name |
| APOLLO | Apple Pattern of Life Lazy Output'er; community tool for extracting knowledgeC.db timelines |
| `com.apple.quarantine` | Extended attribute attached to internet-sourced files by quarantine-aware apps |
| `kMDItemWhereFroms` | Extended attribute storing the source URL(s) of a downloaded file |
| LSQuarantineEventsV2 | SQLite database recording all quarantined download events; persists after file deletion |
| FSEvents | macOS kernel facility tracking filesystem modifications; stored by `fseventsd` in `/.fseventsd/` |
| `.DS_Store` | Binary Finder metadata file present in every directory Finder has visited |
| `com.apple.sharedfilelist` | macOS mechanism for recent items / shared file lists (`.sfl2` binary plists) |
| APFS snapshot | Copy-on-write frozen filesystem state; mountable read-only for point-in-time analysis |
| WebKit epoch | Chrome/Safari internal timestamp epoch: microseconds since 1601-01-01 00:00:00 UTC |
| mac_apt | Open-source Python toolkit (Yogesh Khatri) for parsing macOS/iOS artifacts from images or live systems |
| SSV | Signed System Volume — the cryptographically sealed, read-only system partition on macOS 11+ |
| Secure Enclave | Apple Silicon (and T2) hardware security processor holding volume encryption keys |

---

## Further reading

- Apple Platform Security guide (developer.apple.com/documentation/security) — FileVault key hierarchy, Secure Enclave, SSV
- Howard Oakley, Eclectic Light Company (eclecticlight.co) — deep dives on APFS internals, Unified Log behavior, and macOS changes per release
- Sarah Edwards, mac4n6.com — the definitive community resource; APOLLO, knowledgeC.db schema documentation, iOS/macOS artifact research
- Yogesh Khatri, github.com/ydkhatri/mac_apt — mac_apt source, plugin documentation, supported artifact list
- Mandiant (Google Cloud) — "Reviewing macOS Unified Logs" (cloud.google.com/blog/topics/threat-intelligence/reviewing-macos-unified-logs/)
- SUMURI — "macOS 26 Tahoe: New Image Formats for Forensics" (sumuri.com) — ASIF and UDSB implications for acquisition
- `man log`, `man tmutil`, `man xattr`, `man sqlite3`, `man fseventsd` — always consult man pages for exact flag semantics on the target OS version
- [[01-boot-process]] — SSV sealing, APFS volume roles, Secure Enclave boot chain
- [[02-apfs-deep-dive]] — APFS copy-on-write, snapshot mechanics, volume group structure
