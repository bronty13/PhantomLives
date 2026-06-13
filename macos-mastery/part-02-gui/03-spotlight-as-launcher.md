---
title: Spotlight as a Launcher & Everything-Box
part: P02 GUI
est_time: 50 min read + 40 min labs
prerequisites: [00-finder-mastery, 01-window-management]
tags: [macos, spotlight, search, launcher, raycast, alfred, forensics, indexing, mdfind, mdutil]
---

# Spotlight as a Launcher & Everything-Box

> **In one sentence:** Spotlight is simultaneously macOS's search engine, app launcher, calculator, dictionary, and unit converter — all backed by a rich metadata index that is also a forensic goldmine — and once you understand its machinery you can tune it, script it, and decide intelligently whether to replace it with Raycast or Alfred.

## Why this matters

Windows veterans reach for the Start menu or Everything.exe for search. On macOS, Spotlight (`Cmd-Space`) is the primary interface for launching apps, jumping to files, doing quick math, and looking up definitions. It is fast because it queries a pre-built metadata index (not the filesystem in real time), and that index is maintained by a cluster of background daemons that most users never think about.

For a forensics professional, those same daemons — and the index files they write to disk — are artifacts. They record what was on a machine, when files were accessed, and often survive deletion of the original files. Understanding the mechanism is necessary for both defending systems (tuning privacy exclusions) and investigating them.

## Concepts

### 1. The Spotlight Daemon Stack

Spotlight is not one process. It is a layered system:

```
User keypress (Cmd-Space)
        │
        ▼
  Spotlight.app   ←──── renders the UI, forwards queries to MDS
        │
        ▼
    mds           ←──── metadata server (main daemon, PID visible in Activity Monitor)
        │
        ├──► mds_stores   ← index writer/compactor, does the heavy I/O
        ├──► mdworker      ← importer workers (one per file type, sandboxed)
        └──► spotlightknowledged ← machine learning / Siri Suggestions overlay
```

- **`mds`** (Metadata Server) is the always-on service launched by `launchd` via `/System/Library/LaunchDaemons/com.apple.metadata.mds.plist`. It sits on a Mach port and answers queries.
- **`mdworker`** instances are spawned per-format to parse files and feed structured metadata back to `mds`. Each importer lives in `/System/Library/Spotlight/` as a `.mdimporter` bundle. Third-party apps can ship their own importers (e.g. PDF Expert, DEVONthink).
- **`mds_stores`** is the index writer. On Apple Silicon, it uses the Efficiency cluster aggressively and is nearly invisible in day-to-day use; after a major OS upgrade it can spike for 20–60 minutes while reimporting changed schemas.
- **`mediaanalysisd`** / **`photoanalysisd`** — machine-learning image/scene analysis, not directly part of search queries but feeds `kMDItemKeywords` and similar attributes.
- **`spotlightknowledged`** — the "Siri Suggestions" overlay; pulls Contacts, Calendar, and usage patterns into query ranking.

### 2. The Index: `.Spotlight-V100`

Every indexed volume gets a hidden directory at its root:

```
/.Spotlight-V100/
└── Store-V2/
    └── <UUID>/
        ├── store          ← main compressed metadata database
        ├── .store         ← shadow copy
        ├── dbStr-*        ← string tables (searchable content)
        ├── reverseIndex/  ← inverted index for full-text
        └── journal/       ← write-ahead log
```

The UUID is volume-specific and changes on a full rebuild. The `store` database is a proprietary compressed binary format; you cannot read it with `sqlite3`. Commercial forensic tools (Cellebrite Inspector, Magnet Axiom, ArtiFast Mac) parse it natively.

**Per-user index:** Newer macOS versions also maintain a per-user CoreSpotlight index at:

```
~/Library/Metadata/CoreSpotlight/index.spotlightV3/
```

This is where app-surfaced content lives — items registered by third-party apps via the `CoreSpotlight` API (messages, notes, reminders, bookmarks). It uses a different schema from the volume index.

> 🔬 **Forensics note:** The `.Spotlight-V100/Store-V2/<UUID>/store` database is one of the most information-dense artifacts on a Mac. It records `kMDItemLastUsedDate`, `kMDItemUseCount`, `kMDItemDateAdded`, `kMDItemContentModificationDate`, and dozens of other attributes for nearly every file on the volume — including files that have since been deleted. A file's entry can persist in the index until the next full rebuild even after the file is gone. On APFS volumes, combine Spotlight index data with FSEvents (`/private/var/db/diagnostics/` and `.fseventsd/`) for a comprehensive timeline.

### 3. Indexed Metadata Attributes (`kMDItem*`)

Spotlight uses a rich attribute namespace. Key ones for both search and forensics:

| Attribute | Meaning |
|---|---|
| `kMDItemDisplayName` | File display name |
| `kMDItemFSName` | Filesystem name |
| `kMDItemContentType` | UTI (e.g. `public.jpeg`) |
| `kMDItemLastUsedDate` | Last opened timestamp |
| `kMDItemUseCount` | How many times opened |
| `kMDItemDateAdded` | When added to this volume |
| `kMDItemContentCreationDate` | Original creation date |
| `kMDItemContentModificationDate` | Last-modified date |
| `kMDItemAuthors` | Document authors |
| `kMDItemEmailAddresses` | Email addresses in mail messages |
| `kMDItemLatitude` / `kMDItemLongitude` | GPS coords embedded in photos/docs |
| `kMDItemWhereFroms` | Download source URLs (Safari sets this) |
| `kMDItemPixelHeight/Width` | Image dimensions |
| `kMDItemBundleIdentifier` | App bundle ID |
| `kMDItemExecutableArchitectures` | `arm64`, `x86_64`, etc. |

> 🔬 **Forensics note:** `kMDItemWhereFroms` is invaluable. Safari and most download managers write the originating URL here as an extended attribute (`com.apple.quarantine` stores the URL too, but `kMDItemWhereFroms` is in the Spotlight index, survives `xattr -d` removal, and is queryable cross-volume). `mdfind 'kMDItemWhereFroms == "*"'` with a domain pattern finds everything downloaded from a specific site.

### 4. What Spotlight Searches Feel Like vs. What's Happening

When you type in the Spotlight bar:

- **Instant (< 50 ms):** App launch, calculator, unit conversion — these are not index queries; Spotlight hardcodes these handlers.
- **Fast (50–200 ms):** Filename matches — the name is in a B-tree in the index.
- **Slower (200 ms–1 s):** Full-text document content — requires hitting the inverted `reverseIndex/`.

**Built-in non-search functions** — Spotlight handles these without touching the index:

| Input | Result |
|---|---|
| `42 * 6 / 7` | Inline calculator result |
| `sqrt(144)` | Math functions |
| `32°F in Celsius` | Unit conversion |
| `1 USD in JPY` | Live currency conversion (requires network) |
| `define cryptography` | Dictionary definition |
| `AAPL` | Stock quote widget |

> 🪟 **Windows contrast:** Windows Search (since Windows 10) also pre-indexes, but the index lives in `C:\ProgramData\Microsoft\Search\Data\Applications\Windows\` and is a SQL-style ESE (Extensible Storage Engine) database — readable with `esentutl`. macOS's format is proprietary but queried with standard POSIX tools (`mdfind`, `mdls`). The scope of metadata captured by macOS (especially per-file last-used counts and download origins) is wider than the Windows index by default.

### 5. Spotlight vs. Finder Search

These are not the same thing, even though both surface in the UI:

| Dimension | Spotlight | Finder search (`Cmd-F`) |
|---|---|---|
| Backend | `mds` metadata index | `mds` index **+ live filesystem crawl** |
| Scope | All indexed volumes | Current folder or everywhere |
| Latency | Near-instant | Slightly slower for live-crawl fallbacks |
| Query language | `kMDItem` predicates, natural language | Finder's structured filter UI |
| Excludes | Privacy exclusion list | Honoring same exclusion list |
| Hidden files | Not shown by default | Can reveal with `Cmd-Shift-.` |

Finder search is `NSMetadataQuery` (same framework, same index) but adds live `getdirentriesattr()` crawls for newly-created files not yet in the index. For scripting, both `mdfind` and the Finder Smart Folder (`.savedSearch`) files use the same predicate format.

### 6. Spotlight Privacy Exclusions and Index Scope

Spotlight respects an exclusion list at **System Settings → Siri & Spotlight → Spotlight Privacy**. Any folder added here is excluded from indexing. Under the hood, `mds` watches `com.apple.metadata.mds.scan.exclusion` and writes the list to:

```
/private/var/db/Spotlight/com.apple.metadata.mds.plist
```

Volume-level exclusion is a `.metadata_never_index` file at the volume root — place one there and `mds` will not index that entire volume.

> ⚠️ **ADVANCED:** Some sensitive working directories (password vaults, encrypted sparse bundles, large video projects) belong in the exclusion list. Indexing an encrypted vault's mount point can leak filenames into the index even if the content is encrypted. Also: major OS upgrades occasionally silently reset the exclusion list. Verify after every upgrade with `mdutil -s /` and by inspecting System Settings → Siri & Spotlight → Privacy.

### 7. Search Operators and Scoping

The Spotlight bar accepts implicit free-text but `mdfind` (the CLI) accepts the full predicate language:

```bash
# Find all PDFs modified in the last 7 days
mdfind 'kMDItemContentType == "com.adobe.pdf" && kMDItemContentModificationDate >= $time.today(-7)'

# Find files with a specific download origin URL
mdfind 'kMDItemWhereFroms == "*evil.example.com*"'

# Scope to a directory (-onlyin)
mdfind -onlyin ~/Documents 'kMDItemTextContent == "*password*"'

# Live streaming: watch new results as they appear (-live)
mdfind -live 'kMDItemFSName == "*.dmg"'

# Interpret as a filename search only (-name flag)
mdfind -name "report 2026"
```

**`mdls`** dumps all indexed attributes for a single file — the metadata equivalent of `stat`:

```bash
mdls ~/Downloads/suspicious.pdf
# Output shows kMDItemWhereFroms, kMDItemDownloadedDate,
# kMDItemContentCreationDate, kMDItemLastUsedDate, etc.
```

**`mdimport`** forces reimport of specific files or directories without rebuilding the full index:

```bash
# Force reimport a single file
sudo mdimport ~/Desktop/newfile.pdf

# List all registered importers
mdimport -L

# Test an importer (shows what attributes it would emit)
mdimport -t -n -d1 ~/Desktop/newfile.pdf
```

### 8. Siri Suggestions vs. Spotlight Search Results

Spotlight mixes two result types:

1. **Index results** — deterministic, from `mds`; reproducible with `mdfind`.
2. **Siri Suggestions** — probabilistic, from `spotlightknowledged`; influenced by usage history, Contacts, Calendar, and Apple Intelligence (macOS 26). These can be disabled independently in System Settings → Siri & Spotlight → Search Results → uncheck "Siri Suggestions."

The Suggestions layer pulls from `knowledgegraphd`, a database at `~/Library/Assistant/SiriVocabulary/` and related paths, which is a separate forensic artifact tracking app usage patterns, contacts accessed, and semantic associations.

---

## Hands-on (CLI & GUI)

### GUI: Spotlight's Full Feature Set

**Launching apps:** Type the first few letters; Spotlight ranks by recency and frequency using its own scoring (not just alphabetical). Press `Cmd-B` on a result to open its enclosing folder instead of launching it. Press `Cmd-Return` to reveal in Finder.

**Calculator:** `Cmd-Space`, then type `(1024 * 1024 * 1024) / (1000 * 1000 * 1000)`. Spotlight shows `1.073741824` inline. No Enter required.

**Unit conversion:** `70 kg in lbs`, `100 mph in kph`, `1 GB in MB`. For currency: `500 EUR in USD` (live rate; needs network).

**Definitions:** `define ephemeral` shows the Dictionary result inline with etymology. Pressing `Return` opens Dictionary.app.

**System shortcuts:** Type `sleep`, `restart`, `shut down`, `lock screen` — Spotlight surfaces system commands directly (macOS 26 Tahoe added more of these).

**Web search:** Any query that does not resolve locally gets a "Search the Web" result at the bottom. You can also type `!` before a query to send it directly to the default browser (undocumented but works on some configurations).

### CLI: Index Inspection

```bash
# Check indexing status for all volumes
mdutil -s -a

# Expected output on a healthy system:
# /:
#         Indexing enabled.
# /Volumes/MyDisk:
#         Indexing enabled.

# Dump all metadata for a file
mdls /Applications/Safari.app

# Search by kind — 'kind:' is the natural-language operator in the GUI
# but in mdfind you use the UTI
mdfind 'kMDItemContentType == "com.apple.application-bundle"' -onlyin /Applications | head -20

# Find recently opened documents (last 24h)
mdfind 'kMDItemLastUsedDate >= $time.today(-1)'

# Find images with GPS data
mdfind 'kMDItemLatitude == "*"' -onlyin ~/Pictures
```

---

## Labs

### Lab 1: Spotlight Scavenger Hunt

No setup needed. Open Spotlight and try each of these in sequence, noting response time:

1. Type `1337 * 42` — confirm inline calculator.
2. Type `define exfiltration` — confirm dictionary result.
3. Type `100 Fahrenheit in Celsius` — confirm `37.778°C`.
4. Type `Safari` — confirm it ranks first; press `Cmd-Return` to reveal the `.app` in Finder.
5. Type your own name — observe what Spotlight finds (contacts, documents, emails).

### Lab 2: CLI Metadata Inspection

```bash
# 1. Inspect your own Terminal app
mdls /Applications/Terminal.app | grep -E 'kMDItemVersion|kMDItemExecutableArchitectures|kMDItemBundleIdentifier'

# 2. Find the 10 most recently used files (any type) on your home directory
mdfind -onlyin ~ 'kMDItemLastUsedDate >= $time.today(-30)' | \
  xargs mdls -name kMDItemLastUsedDate -name kMDItemFSName 2>/dev/null | \
  paste - - | sort -k2 -r | head -20

# 3. Check where a downloaded file came from
# (pick any file in ~/Downloads)
TARGET=$(ls -t ~/Downloads | head -1)
mdls ~/Downloads/"$TARGET" | grep -E 'kMDItemWhereFroms|kMDItemDownloadedDate|kMDItemLastUsedDate'
```

Expected output for step 3 includes the originating URL, the download timestamp, and last-used date — demonstrating the forensic value of the index on a live machine.

### Lab 3: Rebuild the Spotlight Index

> ⚠️ **ADVANCED / DESTRUCTIVE:** This erases the current index and forces a full rebuild. On a large volume the initial rebuild takes 5–60 minutes. Search will return incomplete results during rebuild. No data is lost — this only affects the index, not your files.
>
> **Rollback:** Not needed; the index self-heals. If you want to cancel mid-rebuild: `sudo mdutil -a -i off && sudo mdutil -a -i on` restarts the process cleanly.

```bash
# Step 1: Disable indexing (this also erases the current index files)
sudo mdutil -a -i off

# Verify erasure — the Store-V2 directory should now be empty
ls -la /.Spotlight-V100/Store-V2/

# Step 2: Re-enable — rebuild begins immediately in the background
sudo mdutil -a -i on

# Step 3: Watch mds_stores doing its work
top -pid $(pgrep mds_stores | head -1)
# Or: Activity Monitor → Search "mds_stores"

# Step 4: Check progress (index shows as incomplete until done)
mdutil -s /
# "Indexing enabled." = done; "Indexing enabled. Indexing in Progress." = still building
```

### Lab 4: Exclude a Sensitive Directory

> ⚠️ **ADVANCED:** Adding a folder to exclusions is safe and reversible through System Settings. The CLI path below writes directly to the mds config, which is also safe to reverse.

**GUI method:** System Settings → Siri & Spotlight → Spotlight Privacy → `+` → select folder → Done.

**CLI method** (more scriptable):
```bash
# Exclude ~/Projects/secret from indexing
defaults write com.apple.Spotlight orderedItems -array-add \
  '<dict><key>enabled</key><false/><key>name</key><string>'"$HOME/Projects/secret"'</string></dict>'

# Then tell mds to reload its config
killall -HUP mds

# Verify exclusion by checking what mds thinks
mdutil -s ~/Projects/secret
# Should show: "Indexing disabled."

# To undo: remove via GUI or edit com.apple.Spotlight plist with PlistBuddy
```

### Lab 5: Forensic Query — Reconstruct Recent Activity

This simulates a triage workflow on a live (suspect or own) machine:

```bash
# Files accessed in the last 48 hours
mdfind 'kMDItemLastUsedDate >= $time.today(-2)' | \
  grep -v '\.app$' | head -50

# All documents downloaded from the web in the last 30 days
mdfind 'kMDItemDownloadedDate >= $time.today(-30)' | \
  xargs mdls -name kMDItemFSName -name kMDItemWhereFroms -name kMDItemDownloadedDate 2>/dev/null

# Find executables that were run (use count > 0), scope to non-system paths
mdfind 'kMDItemContentType == "com.apple.application-bundle" && kMDItemUseCount > 0' \
  | grep -v '/System/\|/Library/'

# Find images with embedded GPS data (potential location leak)
mdfind 'kMDItemLatitude >= -90'
```

> 🔬 **Forensics note:** The `kMDItemUseCount` query above is powerful during incident response: it finds apps that have been executed, even if they have since been trashed, as long as the index entry survives. Combine with the APFS `fseventsd` log (see [[01-architecture-apfs]]) and the `LSSharedFileList` recents (`~/Library/Application Support/com.apple.sharedfilelist/`) for a multi-artifact timeline.

### Lab 6: Install and Configure Raycast as Your Default Launcher

> ⚠️ **Note:** This replaces `Cmd-Space` with Raycast. Spotlight remains installed and functional; you are only changing the hotkey assignment. Fully reversible.

**Install:**
```bash
brew install --cask raycast
```

**Configure:**
1. Launch Raycast → onboarding assigns `Cmd-Space` automatically (may prompt you to disable Spotlight's shortcut).
2. To manually release Spotlight's claim: System Settings → Keyboard → Keyboard Shortcuts → Spotlight → uncheck "Show Spotlight search."
3. In Raycast Preferences → Hotkey → set to `Cmd-Space`.

**Verify Raycast capabilities beyond Spotlight:**

| Feature | Spotlight | Raycast (free) | Alfred (Powerpack ~$42) |
|---|---|---|---|
| App launch | Yes | Yes | Yes |
| File search | Yes | Yes | Yes |
| Calculator | Yes | Yes (more functions) | Yes |
| Clipboard history | No | Yes, 30 days | Yes |
| Snippets / text expansion | No | Yes | Yes |
| Window management | No | Yes (tiling) | No (third-party) |
| Extensions/workflows | No | 2,000+ (React/TS) | Mature workflows (PHP-like) |
| Script runner | No | Yes | Yes |
| Floating notes | No | Yes (Pro, $8/mo) | No |
| One-time purchase | — | Free tier sufficient | ~$42, forever |

**Try these in Raycast immediately:**
- `Cmd-Space`, type `clip` → Clipboard History → browse your last 20 copied items
- `Cmd-Space`, type `win` → Window Management → "Left Half" tiles the frontmost window
- `Cmd-Space`, type `snip` → Snippets → create a snippet `;addr` → your address
- Install the GitHub extension: Raycast Store → GitHub → now `Cmd-Space` + `repo` searches your repos directly

---

## Pitfalls & Gotchas

**Index lag on new files.** Files written to disk appear in Spotlight searches within seconds under normal conditions, but write bursts (compilation output, large unzips) can lag 30–60 seconds. `mdfind -live` streams new results as they index.

**Spotlight doesn't index everything.** By default it skips: files in exclusion list, volumes with `.metadata_never_index`, most of `/private/`, system volumes (sealed System volume is not user-writable and is indexed read-only), and files inside encrypted containers that are not mounted. A truecrypt-style encrypted volume shows zero internal files in Spotlight when unmounted.

**macOS 26 memory leak.** Early Tahoe betas had `mds_stores` consuming 40–60 GB RAM during the post-upgrade reindex. The fix: force a clean rebuild with `sudo mdutil -a -i off && sudo mdutil -a -i on` rather than waiting for the runaway process. Monitor in Activity Monitor if you see a post-upgrade slowdown.

**Major upgrades reset Privacy exclusions.** This is a documented recurring issue. After any major upgrade, go to System Settings → Siri & Spotlight → Spotlight Privacy and verify your exclusions survived.

**`mdutil -a -i off` vs `mdutil -a -d`.** The `-i off` flag sets the indexer to `kMDConfigSearchLevelFSSearchOnly` — indexing stops but search still works against existing data. The `-d` flag sets `kMDConfigSearchLevelOff` — kills both indexing and search. Use `-d` on sensitive analysis machines; use `-i off` if you want search to keep working against the existing index while pausing updates.

**Raycast vs. Alfred choice.** Raycast's free tier wins on raw features in 2026. Alfred's edge: one-time purchase (no subscription for core features), mature workflow ecosystem for power users who have invested years in Alfred workflows, and slightly faster cold-launch on heavily loaded systems. For new macOS switchers with no Alfred workflow library, Raycast is the practical default.

**`Cmd-Space` hotkey conflicts.** Some apps (JetBrains IDEs, many games) grab `Cmd-Space` globally. When Raycast fails to open, check System Preferences → Keyboard Shortcuts → App Shortcuts and look for conflicts. `lsof` on the Mach port is not practical here; use System Preferences as the authoritative view.

**Privacy: Siri Suggestions phone home.** `spotlightknowledged` sends anonymized query data to Apple for Siri Suggestions ranking unless you disable it. System Settings → Siri & Spotlight → Search Results → uncheck "Siri Suggestions" and "Allow Spotlight Suggestions in Look Up." This also disables the stock quote widget and live currency conversion — trade-off to be aware of.

---

## Key Takeaways

1. Spotlight is an `mds`-backed metadata index, not a real-time filesystem crawler. Understanding the index format (`.Spotlight-V100/Store-V2/<UUID>/store`) unlocks both forensic investigation and precise `mdfind` queries.

2. `mdfind` and `mdls` give you full programmatic access to the same index Spotlight queries — essential for scripted triage and incident response.

3. The `kMDItemWhereFroms`, `kMDItemLastUsedDate`, and `kMDItemUseCount` attributes persist in the index even after file deletion, making Spotlight a high-value forensic artifact that often outlives the FSEvents log.

4. `mdutil -a -i off` pauses indexing; `mdutil -a -i off && mdutil -a -i on` forces a full index rebuild (the correct response to post-upgrade index corruption or the Tahoe memory-leak bug).

5. Raycast's free tier meaningfully extends the Spotlight model with clipboard history, snippets, window management, and a 2,000+ extension ecosystem — all invoked through the same `Cmd-Space` muscle memory.

---

## Terms Introduced

| Term | Definition |
|---|---|
| `mds` | Metadata Server — the always-on Spotlight daemon |
| `mds_stores` | Spotlight index writer/compactor subprocess |
| `mdworker` | Per-format importer worker process (sandboxed) |
| `mdutil` | CLI tool to manage Spotlight indexing state per volume |
| `mdfind` | CLI tool to query the Spotlight index with predicates |
| `mdls` | CLI tool to dump all Spotlight metadata attributes for a file |
| `mdimport` | CLI tool to force reimport of files into the index |
| `.Spotlight-V100` | Hidden root-level directory containing the volume's Spotlight index |
| `Store-V2` | Subdirectory format for the actual index database inside `.Spotlight-V100` |
| `kMDItem*` | Spotlight metadata attribute namespace (e.g. `kMDItemLastUsedDate`) |
| `kMDItemWhereFroms` | Spotlight attribute storing a file's originating download URL |
| `spotlightknowledged` | Siri Suggestions / machine learning layer on top of raw Spotlight |
| `CoreSpotlight` | API framework for third-party apps to add content to the Spotlight index |
| `NSMetadataQuery` | Cocoa class that drives Spotlight queries from app code and Finder |
| Raycast | Free macOS launcher replacing Spotlight; adds clipboard, snippets, extensions |
| Alfred | Commercial macOS launcher (Powerpack ~$42 one-time); mature workflow ecosystem |
| `.metadata_never_index` | File placed at a volume root to prevent Spotlight from indexing it |

---

## Further Reading

- **Apple Platform Security Guide** — covers `mds` trust model and SIP protection of the system volume index
- Howard Oakley, *The Eclectic Light Company* — ["Can you disable Spotlight and Siri in macOS Tahoe?"](https://eclecticlight.co/2026/01/16/can-you-disable-spotlight-and-siri-in-macos-tahoe/) — definitive technical analysis of `mdutil` flag behavior in macOS 26
- 504ENSICS Labs — ["Forensic Analysis of the OS X Spotlight Search Index"](https://www.504ensics.com/forensic-analysis-of-the-os-x-spotlight-search-index/) — research-grade breakdown of the binary format
- Forensafe — ["Apple Spotlight"](https://www.forensafe.com/blogs/apple-spotlight.html) — forensic artifact enumeration with per-attribute forensic value ratings
- `man mdfind`, `man mdls`, `man mdutil`, `man mdimport` — all locally available; read the PREDICATE FORMAT section of `man mdfind`
- Raycast documentation — [raycast.com/extensions](https://raycast.com/extensions) — extension API and store
- Related lessons: [[00-finder-mastery]] (Finder search vs. Spotlight), [[01-window-management]] (Raycast window tiling in context), and (upcoming) the forensics part for deeper artifact analysis

---

*Part P02 · Lesson 03 of the macOS Mastery curriculum*
