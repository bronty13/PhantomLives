---
title: Essential Unix Commands
part: P03 CLI
est_time: 60 min read + 45 min labs
prerequisites: [02-terminal-shell-basics]
tags: [macos, cli, unix, bsd, filesystem, apfs, xattr, acl, forensics]
---

# Essential Unix Commands

> **In one sentence:** macOS ships BSD userland — not GNU — so the flags you memorized on Linux don't all work, and the platform adds APFS-native operations, extended-attribute visibility, and ACL display that have no direct Windows or Linux equivalent.

---

## Why this matters

Every forensic investigation, build pipeline, and admin script starts here. Knowing *which* implementation you're running (BSD vs. GNU vs. Apple's own fork), *where* the binaries live, and *what metadata layer exists beneath the POSIX surface* is the difference between a correct analysis and a silent miss. A `cp` that drops extended attributes or a `zip` that scatters `._` AppleDouble files can corrupt evidence or break deployments. Knowing the right incantation — and *why* it's right — is the floor of macOS power use.

> 🪟 **Windows contrast:** Windows ships PowerShell cmdlets and `cmd.exe` builtins with no POSIX layer unless you install WSL or Cygwin. macOS has native BSD Unix underneath Aqua; the terminal is a first-class engineering surface, not an afterthought.

---

## Concepts

### BSD vs. GNU: The Fork That Matters

macOS userland is derived from FreeBSD/NetBSD. Most standard tools live in `/bin`, `/usr/bin`, and `/usr/sbin`. Apple ships its own patched versions, occasionally adding Apple-specific flags (e.g., `ls -O` for file flags, `cp -c` for clonefiles). They do **not** ship GNU coreutils.

Critical consequence: flags differ. `ls --color` is GNU-only; `ls -G` enables color on BSD. `sed -i ''` (BSD) vs. `sed -i` (GNU). `stat -x` (BSD verbose) vs. `stat -c '%s'` (GNU format). If you paste a Linux one-liner into macOS and it fails silently or produces garbage output, BSD/GNU divergence is suspect #1.

Install GNU coreutils via Homebrew to get both:

```bash
brew install coreutils   # gls, gstat, gsed, gawk, etc. — prefixed g*
brew install gnu-sed     # gsed
brew install findutils   # gfind, gxargs, glocate
```

GNU tools install with a `g` prefix by default. To override the BSD versions in your PATH, Homebrew prints the shim path; add it **carefully** — some macOS tooling depends on BSD flag semantics.

> 🔬 **Forensics note:** When parsing outputs from macOS systems in scripts, always confirm which implementation produced them. A log or artifact exported from macOS may use BSD date formats (`Mon Jun 13 08:00:00 2026`) that GNU tools parse differently.

---

### The Metadata Iceberg: Flags, xattrs, and ACLs

POSIX `rwxr-xr-x` is only the top of macOS's permission stack. Three additional layers exist:

```
┌──────────────────────────────────────────────────────┐
│  POSIX mode bits    (chmod, ls -l)                   │
├──────────────────────────────────────────────────────┤
│  BSD file flags     (chflags, ls -O)  — uchg, hidden │
├──────────────────────────────────────────────────────┤
│  Extended attributes (xattr, ls -@)  — com.apple.*   │
├──────────────────────────────────────────────────────┤
│  POSIX ACLs         (chmod +a, ls -e)                │
└──────────────────────────────────────────────────────┘
```

**BSD file flags** are set by `chflags` and stored in the inode's `st_flags` field. Key flags:
- `uchg` — user immutable; even root needs `sudo chflags nouchg` to remove it
- `schg` — system immutable; requires SIP-off or recovery mode
- `hidden` — tells Finder to hide the file (like the Windows hidden attribute)
- `nodump` — exclude from traditional Unix dump backups

**Extended attributes (xattrs)** are arbitrary key/value blobs attached to a file's inode — not its data fork. They are how Gatekeeper stores quarantine (`com.apple.quarantine`), how Finder stores custom icons (`com.apple.FinderInfo`), how Spotlight stores metadata. In macOS Tahoe 26, xattr names can carry preservation-behavior flags after a `#` separator (e.g., `com.apple.lastuseddate#PS` — the P means "preserve on copy but don't export," S means "sync to iCloud Drive"). See `man xattr` for the flag semantics.

**POSIX ACLs** grant fine-grained `allow`/`deny` entries beyond the owner/group/other triplet. Common in corporate environments with Directory Service integration.

---

## Hands-on (CLI & GUI)

### Navigation and Inspection

#### `ls` — All the flags that matter

```bash
ls -l          # long listing: mode, links, owner, group, size, mtime, name
ls -la         # include dotfiles
ls -lh         # human-readable sizes (1.2M, 4.0K)
ls -lS         # sort by size descending
ls -lt         # sort by modification time, newest first
ls -ltr        # reverse: oldest first (good for log dirs)
ls -G          # colorized output (BSD's --color)
ls -@          # show extended attribute names for each file
ls -O          # show BSD file flags (e.g., uchg, hidden, nodump)
ls -e          # show POSIX ACLs inline
ls -le@        # the forensics triple: flags + ACLs + xattrs in one pass
```

Example output of `ls -le@ /etc/hosts`:
```
-rw-r--r--  1 root  wheel  - 213 Jun 12 09:00 /etc/hosts
  com.apple.provenance
```

The `-` after `wheel` is the flags column (empty = no BSD flags). The indented line is the xattr name. Add `-e` to see ACEs if any exist. Add `-O` to see flag names like `uchg` instead of `-`.

```bash
# See everything on a quarantined file:
ls -le@ ~/Downloads/SomeApp.dmg
# Look for: com.apple.quarantine xattr, possible uchg flag
```

> 🔬 **Forensics note:** The `com.apple.quarantine` xattr is written by any process that calls `LSSetItemAttribute` with the quarantine flag — Safari, Chrome, Mail, curl with the right flags, App Store. Its value encodes a 16-bit flag word, a UUID, the originating app bundle ID, and the source URL. `xattr -p com.apple.quarantine <file>` reveals all of it. This is Tier-1 evidence for determining how a file arrived on disk.

#### `pwd`, `cd`, `pushd`/`popd`

```bash
pwd               # print working directory (resolves symlinks by default)
pwd -P            # resolve to physical path (follow all symlinks)
cd -              # go back to previous directory
pushd /tmp        # push current dir to stack, cd to /tmp
popd              # pop stack, return to previous dir
dirs -v           # show full stack with indices
cd ~3             # jump to index 3 in dirs stack
```

#### `tree` (via Homebrew)

`tree` is not in macOS base. `brew install tree`.

```bash
tree -L 2                 # 2 levels deep
tree -a                   # include dotfiles
tree -I "*.pyc|node_modules|.git"   # ignore patterns
tree --du -h              # show disk usage per node
tree -J                   # output JSON (scriptable)
```

#### `stat` — inode details

BSD `stat` on macOS differs from GNU `stat`:

```bash
stat -x /etc/hosts           # verbose BSD format: all timestamps, inode, flags
stat -f "%z bytes, inode %i, links %l" /etc/hosts   # custom format
stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" /etc/hosts     # mtime formatted
```

> 🔬 **Forensics note:** `stat -x` shows all three timestamps: access (atime), modify (mtime), and change (ctime — inode change, NOT creation). On APFS, there is also a **birth time** (crtime). Retrieve it with: `GetFileInfo -d <file>` or via `mdls -name kMDItemFSCreationDate <file>`. APFS birth times survive most copies and are reliable evidence of when a file was first created — unlike mtime which any `touch` can reset.

---

### File Operations

#### `cp` — copies with APFS superpowers

```bash
cp -i src dst           # interactive: prompt before overwrite
cp -n src dst           # no-clobber: skip if dst exists
cp -r src/ dst/         # recursive directory copy
cp -p src dst           # preserve mode, ownership, timestamps
cp -a src dst           # archive mode = -pPR (preserves symlinks, attrs)
cp -c src dst           # APFS clone: calls clonefile(2), zero bytes copied
cp -X src dst           # do NOT copy extended attributes (strips xattrs)
```

**`cp -c` (clonefile)** is APFS-only and deserves special attention. It creates a new inode that shares the source's data extents at the block level — copy-on-write. The clone is instantaneous regardless of file size: copying a 50 GB Xcode archive takes the same wall-clock time as copying a text file. The two copies diverge lazily as blocks are modified. This is how Finder's "Duplicate" works internally.

Limitations: source and destination must be on the same APFS volume; `cp -c` on a non-APFS filesystem silently falls back to a regular copy; directories clone as if each file is cloned individually (per `clonefile(2)` man page), which is fine but not atomic — use Finder Duplicate or `copyfile(3)` for directory trees where atomicity matters.

> 🔬 **Forensics note:** Files created via clonefile share block pointers at the filesystem layer. `diskutil apfs listSnapshots` and APFS internal B-tree tooling can reveal clone relationships. In a forensic image, two files with identical content and size but different inodes may be APFS clones rather than independent copies — this distinction affects deduplication analysis and chain-of-custody interpretations.

#### `mv`, `rm`

```bash
mv -i src dst          # prompt before overwriting
mv -n src dst          # never overwrite
rm -i file             # interactive confirmation per file
rm -rf dir/            # recursive force — no confirmation, no undo
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `rm -rf` is permanent and immediate on APFS. There is no Trash. No undo. Before running `rm -rf` on anything non-trivial, snapshot or verify you have a backup. On APFS, `tmutil snapshot` creates an instant local Time Machine snapshot: `sudo tmutil snapshot`. Roll back: `tmutil listlocalsnapshots /` then boot to Recovery and use Migration Assistant or `mount` the snapshot. Better yet, move to Trash via `mv file ~/.Trash/` if interactive.

#### `ln` — hard links and symlinks

```bash
ln target linkname         # hard link: same inode, same data, same directory restriction
ln -s target linkname      # symbolic link: stores path string, cross-volume OK
ln -sf target linkname     # force: overwrite existing symlink
readlink -f linkname       # resolve symlink chain to canonical path
```

Hard links cannot span volumes or point to directories (without HFS+ tricks). They're how Time Machine achieves "free" incremental backups — unchanged files are hard-linked between snapshots, consuming no additional space.

#### `mkdir`, `touch`

```bash
mkdir -p a/b/c/d           # create full path, no error if exists
touch file                 # create empty file OR update mtime to now
touch -t 202506130900 file # set mtime to specific timestamp (YYYYMMDDhhmm)
touch -r reference file    # set mtime/atime of file to match reference file
```

> 🔬 **Forensics note:** `touch -r` is the attacker's timestamp-manipulation tool. If a suspicious file has the same timestamps as a known-good system file, that's a red flag. Cross-check birth time via `mdls` — birth time is harder to fake without root and low-level APFS writes.

---

### `ditto` vs `cp` for Mac-correct copies

`ditto` is Apple's canonical high-fidelity copy tool. It preserves:
- Both data fork and resource fork
- Extended attributes (all of them, including `com.apple.quarantine`)
- HFS+ compression (if applicable)
- BSD file flags
- POSIX ACLs

```bash
ditto src dst                    # copy file or directory (recursive, preserves everything)
ditto --noextattr src dst        # copy without extended attributes
ditto --norsrc src dst           # copy without resource forks
ditto -V src dst                 # verbose (shows each file copied)

# Create a proper Mac zip (no AppleDouble files):
ditto -c -k --sequesterRsrc --keepParent src/ archive.zip

# Expand a Mac zip:
ditto -x -k archive.zip dst/
```

**The AppleDouble problem with `/usr/bin/zip`:** When you run `zip -r archive.zip SomeDir/` on macOS, zip creates `._filename` AppleDouble files inside the archive for every file that has a resource fork or certain xattrs. These `._` files are junk on Linux/Windows and litter the extraction. `ditto -c -k` uses the same zip format but stores resource forks and xattrs inside a `__MACOSX/` sidecar directory in a format that macOS can transparently reconstruct — cleaner, but still annoying on other platforms.

> 🔬 **Forensics note:** The presence of `__MACOSX/` directories and `._` files in an archive is a reliable indicator that the archive was created on macOS. The `._` header encodes the file's `com.apple.FinderInfo` blob, which can reveal the Finder label color, Spotlight comment, custom icon flag, and other metadata. `file ._MyFile` and `xattr -l` on the extracted content reveals it.

---

### `rsync` — Now openrsync

macOS Sequoia 15 (and therefore Tahoe 26) replaced `/usr/bin/rsync` v2.6.9 with **openrsync**, an ISC-licensed reimplementation. It reports `rsync version 2.6.9 compatible` but is a different binary. It is missing a subset of rsync 3.x flags. Scripts relying on `--progress`, `--info=progress2`, `--log-file`, or advanced filter rules may break.

```bash
rsync --version                 # confirms openrsync on macOS 15+
rsync -avz src/ user@host:dst/  # basic remote push (works)
rsync -a --delete src/ dst/     # mirror with deletion (works)
```

For serious use, install real rsync 3.x:

```bash
brew install rsync              # installs to /opt/homebrew/bin/rsync
which rsync                     # should now show Homebrew path
rsync --version                 # rsync 3.4.x
```

Common power flags (rsync 3.x):
```bash
rsync -aHAX src/ dst/           # -H: hard links, -A: ACLs, -X: xattrs
rsync -avz --progress src/ dst/ # human-readable progress
rsync -n --itemize-changes src/ dst/  # dry run: what would change?
rsync --exclude='*.DS_Store' --exclude='.Trash' src/ dst/
```

> ⚠️ **ADVANCED:** Running `brew install rsync` shadows `/usr/bin/rsync` in your PATH. Some Apple tools (e.g., older Xcode scripts, third-party backup agents) call `/usr/bin/rsync` directly and will still get openrsync. Your shell will use Homebrew rsync. This split is usually fine but be aware of it.

---

### Viewing File Contents

```bash
cat file                  # concatenate to stdout; -n adds line numbers
cat -A file               # show non-printing chars (^I for tab, $ for newline)
less file                 # pager: j/k to scroll, /pattern to search, q to quit
less +F file              # follow mode (like tail -f but with scroll-back)
head -n 20 file           # first 20 lines
tail -n 50 file           # last 50 lines
tail -f /var/log/system.log   # follow appends in real time
tail -F /path/to/log      # follow even if file is rotated (re-opens on rename)
```

**`bat`** (`brew install bat`) is `cat` with syntax highlighting, line numbers, git diff markers in the gutter, and automatic paging. It uses the same language grammars as VS Code. Replaces `cat` for interactive use; plain `cat` still for scripts.

```bash
bat file.py               # highlighted Python
bat --plain file          # no decorations (pipe-safe)
bat -l json file.txt      # force JSON syntax on a mis-named file
bat --diff file           # show only changed sections vs git HEAD
```

---

### Finding Files

#### `find` — BSD implementation

macOS ships BSD `find`, not GNU `find`. Most common options are compatible, but some GNU extensions (e.g., `-printf`) don't exist.

```bash
find . -name "*.log"                          # by name glob
find . -iname "*.log"                         # case-insensitive
find . -type f                                # files only (d=dir, l=symlink, p=pipe)
find . -type f -size +10M                     # files over 10 MB
find . -mtime -1                              # modified in last 24 hours
find . -mtime +30                             # modified more than 30 days ago
find . -newer /tmp/reference                  # newer than reference file
find . -name "*.py" -print0 | xargs -0 grep "import os"   # NUL-safe pipeline
find . -perm -u+x -type f                     # user-executable files
find . -flags uchg                            # files with user-immutable flag (BSD-only)
find /private/var/folders -name "com.apple.LaunchServices*" 2>/dev/null
```

`-print0` + `xargs -0` is essential when filenames contain spaces or newlines. Never use `find ... | xargs` without `-print0`/`-0` on macOS where filenames commonly have spaces.

> 🔬 **Forensics note:** `find / -flags uchg 2>/dev/null` finds every user-immutable file — a quick sweep for persistence mechanisms that set this flag to prevent deletion. Combine with `-mtime -7` to narrow to recently modified immutable files.

#### `mdfind` — Spotlight from the CLI

`locate` was removed from macOS years ago (the `locatedb` update daemon was never default-enabled and was silently dropped). The correct replacement is `mdfind`, which queries the same Spotlight index that drives `Cmd-Space`.

```bash
mdfind "kMDItemDisplayName == 'notes.txt'"        # exact name
mdfind -name "notes.txt"                          # shorthand for name search
mdfind -onlyin ~/Documents "kMDItemTextContent == 'APFS'"   # full-text in scope
mdfind "kMDItemKind == 'PDF Document'"            # by file kind
mdfind "kMDItemFSSize > 1000000000"               # files over 1 GB
mdfind "kMDItemDateAdded >= $time.this_week()"   # added this week
mdfind -live "kMDItemFSName == '*.dmg'"           # live: update as index changes
```

`mdls <file>` shows all Spotlight metadata attributes for a file — creation date, kind, pixel dimensions, author, even text content for indexed documents. `mdutil -s /` shows Spotlight indexing status for each volume.

> 🔬 **Forensics note:** The Spotlight store for a volume lives at `/.Spotlight-V100/` (on HFS+/APFS). Its SQLite databases (`store.db`) contain a reverse-text index and all metadata attributes Apple has imported. On a forensic image, parsing the Spotlight store can reconstruct deleted files' metadata long after the files are gone — the index entry may persist. Tools like `spotlight_parser` (open source) and commercial forensic suites (Cellebrite, BlackBag) can parse these offline.

---

### Diff and Comparison

```bash
diff file1 file2               # classic unified diff output
diff -u file1 file2            # unified format (most readable, used by git)
diff -r dir1/ dir2/            # recursive directory comparison
diff -i file1 file2            # case-insensitive
diff --color file1 file2       # colored output (GNU diff only; use via gfind/gdiff)

cmp file1 file2                # byte-by-byte: silent if identical, offset on first diff
cmp -l file1 file2             # list every differing byte (octal offset + values)

comm file1 file2               # compare sorted files: 3 columns (only-f1, only-f2, both)
comm -13 file1 file2           # only lines in file2 (set difference)
comm -12 file1 file2           # only lines in both (intersection)

vimdiff file1 file2            # side-by-side in vim with sync scrolling
```

> 🔬 **Forensics note:** `cmp -l` is the tool for binary comparison of disk images or firmware blobs. For cryptographic verification, use `shasum -a 256 file` (built-in) or `md5 file` (legacy; avoid for security purposes). Never use `md5` to verify download integrity — use `shasum -a 256`.

---

### Archives

#### `tar`

```bash
tar -czf archive.tar.gz dir/       # create gzip-compressed tar
tar -cJf archive.tar.xz dir/       # create xz-compressed tar (best ratio)
tar -xzf archive.tar.gz            # extract gzip tar
tar -xzf archive.tar.gz -C /tmp/   # extract to specific directory
tar -tzf archive.tar.gz            # list contents without extracting
tar -czf - dir/ | ssh host "cat > /remote/archive.tar.gz"   # stream to remote

# Exclude common Mac cruft:
tar -czf archive.tar.gz dir/ \
  --exclude='.DS_Store' \
  --exclude='__MACOSX' \
  --exclude='._*' \
  --exclude='.Trash'
```

macOS `tar` supports `--disable-copyfile` to suppress AppleDouble `._` files in archives and `COPYFILE_DISABLE=1` as the equivalent environment variable for non-tar tools.

#### `zip`/`unzip`

```bash
zip -r archive.zip dir/            # recursive zip (creates ._* for xattr-bearing files)
COPYFILE_DISABLE=1 zip -r archive.zip dir/   # suppress AppleDouble files
unzip archive.zip                  # extract
unzip -l archive.zip               # list contents
unzip archive.zip -d /tmp/dest/    # extract to directory
```

#### `ditto` for Mac-correct zips (preferred)

```bash
# Create Mac-native zip preserving resource forks and xattrs cleanly:
ditto -c -k --sequesterRsrc --keepParent MyApp.app MyApp.zip

# Expand:
ditto -x -k MyApp.zip ./
```

Always use `ditto -c -k` when zipping `.app` bundles or any directory you intend to re-deploy on macOS. Plain `zip` corrupts quarantine xattrs and may strip resource forks.

#### `hdiutil` — disk images

```bash
hdiutil create -size 500m -fs APFS -volname "Scratch" scratch.dmg   # create DMG
hdiutil attach scratch.dmg                                           # mount
hdiutil detach /Volumes/Scratch                                      # unmount
hdiutil convert scratch.dmg -format UDZO -o compressed.dmg          # compress
hdiutil verify compressed.dmg                                        # verify checksum
hdiutil imageinfo disk.dmg                                           # metadata dump
```

> 🔬 **Forensics note:** `hdiutil imageinfo` reveals the DMG partition scheme, block size, sector count, and any embedded encryption. `hdiutil attach -readonly` mounts a DMG without writing to it — essential for evidence preservation. DMGs support GUID, APM, and MBR partition tables; `hdiutil attach -verbose` will show the mapping.

#### Compression utilities

```bash
gzip file              # compress in-place → file.gz (removes original)
gzip -d file.gz        # decompress (or gunzip file.gz)
gzip -k file           # keep original
bzip2 / bunzip2        # same pattern, better ratio, slower
xz / unxz             # best ratio, slowest; ubiquitous in Linux packages
zstd file              # modern: fast + good ratio; brew install zstd
```

---

### Tool Discovery: `which`, `type`, `command -v`

```bash
which rsync            # first match in PATH; returns first found
which -a rsync         # all matches in PATH
type rsync             # shell built-in vs. function vs. external binary
command -v rsync       # POSIX-standard: silent if not found, returns 0 or 1
```

`type` and `command -v` are shell built-ins that see shell aliases and functions; `which` is an external binary that only sees PATH. Use `type` when debugging "why is this not running what I think."

```bash
type ls        # may show: ls is an alias for ls -G  (if you've aliased it)
type cd        # cd is a shell builtin
which cd       # (no output — builtins have no filesystem path)
```

---

### `man` and `tldr`

```bash
man ls                 # BSD man page; q to quit, /pattern to search
man -k "extended attr" # search man page names and descriptions
man 2 clonefile        # section 2 = system calls; man 3 = library functions
open man:ls            # open man page in a browser (macOS extension)
```

`tldr` (`brew install tldr`) shows community-sourced practical examples for commands, skipping the reference material and showing the 5 things people actually run:

```bash
tldr rsync
tldr tar
tldr find
```

---

### Disk Usage: `du`, `df`, `ncdu`

```bash
df -h                  # disk free: all mounted volumes, human-readable
df -H                  # same but 1000-based prefixes (MB vs. MiB)

du -sh /Applications/  # summarize total size of directory
du -sh */              # sizes of all children in current dir
du -sh * | sort -rh | head -20   # top-20 largest children

# APFS caveat: du reports "logical" size, not physical.
# Cloned files are counted multiple times even though they share blocks.
# diskutil apfs list shows "Physical Used" (actual block usage).
```

**`ncdu`** (`brew install ncdu`) is the power tool: interactive TUI disk usage browser with sort, delete, and drill-down. Faster than du on large trees.

```bash
ncdu /              # interactive scan from root (use sudo for full access)
ncdu -x /           # stay on one filesystem (don't cross mounts)
```

> 🪟 **Windows contrast:** Windows has no built-in du equivalent in cmd.exe. PowerShell's `Get-ChildItem -Recurse | Measure-Object -Property Length -Sum` is slow and misses junction points. On macOS, `du` is instant-ish because it reads inode sizes without opening files.

> 🔬 **Forensics note:** `du -sh --apparent-size` vs. `du -sh` reveals sparse files — a file that appears to be 10 GB but uses 100 KB on disk is sparse. Sparse files are common in VM disk images and database files; a mismatch warrants investigation.

---

## 🧪 Labs

### Lab 1: The ls Metadata Deep-Dive

Explore the full metadata stack on a downloaded file:

```bash
# Download something (or use any existing download):
curl -L -o /tmp/test.dmg "https://download.iterm2.com/files/iTerm2-3_5_0.dmg" 2>/dev/null || \
  touch /tmp/test.dmg && xattr -w com.apple.quarantine "0083;64b2a000;Safari;|com.apple.Safari" /tmp/test.dmg

# Show all three metadata layers:
ls -le@ /tmp/test.dmg
xattr -l /tmp/test.dmg            # full xattr names + values (hex)
xattr -p com.apple.quarantine /tmp/test.dmg 2>/dev/null || echo "no quarantine"

# Add an ACE and observe:
chmod +a "$(whoami) allow read" /tmp/test.dmg
ls -le /tmp/test.dmg              # ACE appears under the file
chmod -a "$(whoami) allow read" /tmp/test.dmg   # remove it
```

**Expected output:** `ls -le@` shows three sections: the standard long listing, indented xattr names, and (if ACEs exist) `0: user:yourname allow read`.

---

### Lab 2: APFS Clone vs. Regular Copy

Verify that `cp -c` creates a space-free clone, then confirm with `diskutil`:

```bash
# Create a 200 MB test file:
mkfile -n 200m /tmp/original.bin

# Check disk usage before:
df -h /tmp

# Regular copy (copies bytes):
time cp /tmp/original.bin /tmp/regular_copy.bin

# APFS clone (calls clonefile):
time cp -c /tmp/original.bin /tmp/apfs_clone.bin

# Disk usage after — should not have grown by 400 MB:
df -h /tmp

# Confirm they are NOT the same inode (unlike hard links):
stat -f "inode: %i" /tmp/original.bin /tmp/regular_copy.bin /tmp/apfs_clone.bin

# Verify clone is initially identical:
cmp /tmp/original.bin /tmp/apfs_clone.bin && echo "IDENTICAL"

# Modify the clone and watch it diverge (CoW):
printf "MODIFIED" | dd of=/tmp/apfs_clone.bin bs=8 count=1 conv=notrunc 2>/dev/null
cmp /tmp/original.bin /tmp/apfs_clone.bin || echo "DIVERGED (as expected)"

# Cleanup:
rm /tmp/original.bin /tmp/regular_copy.bin /tmp/apfs_clone.bin
```

**Expected output:** `cp -c` is dramatically faster (sub-second for 200 MB vs. measurable for `cp`). `df` shows minimal change. The `stat` inodes differ (it's a clone, not a hard link). After the `dd` write, `cmp` reports divergence.

> ⚠️ **Note:** If `/tmp` is a RAM disk or non-APFS volume, `cp -c` silently falls back to a regular copy. Run `diskutil info /tmp | grep "File System"` to verify APFS.

---

### Lab 3: Mac-Correct Zip with `ditto`

Compare what a plain `zip` and a `ditto` zip produce:

```bash
# Create a test directory with an app-like structure:
mkdir -p /tmp/TestBundle/Contents/MacOS
touch /tmp/TestBundle/Contents/Info.plist
cp /bin/ls /tmp/TestBundle/Contents/MacOS/TestApp
xattr -w com.apple.quarantine "0083;64b2a000;Safari;|com.apple.Safari" /tmp/TestBundle/Contents/MacOS/TestApp

# Plain zip:
cd /tmp && zip -r /tmp/plain.zip TestBundle/
unzip -l /tmp/plain.zip | grep "_\."   # look for ._* AppleDouble files

# ditto zip:
ditto -c -k --sequesterRsrc --keepParent /tmp/TestBundle /tmp/ditto.zip
unzip -l /tmp/ditto.zip | head -20     # cleaner: __MACOSX/ sidecar or nothing

# Expand ditto zip and verify xattrs survived:
mkdir /tmp/ditto_expanded
ditto -x -k /tmp/ditto.zip /tmp/ditto_expanded/
xattr /tmp/ditto_expanded/TestBundle/Contents/MacOS/TestApp

# Cleanup:
rm -rf /tmp/TestBundle /tmp/plain.zip /tmp/ditto.zip /tmp/ditto_expanded
```

**Expected output:** `plain.zip` may contain `._TestApp` entries; `ditto.zip` avoids them and preserves the quarantine xattr through the round-trip.

---

### Lab 4: Find + mdfind Comparison

```bash
# Find recently modified shell scripts:
find ~ -name "*.sh" -mtime -7 -type f 2>/dev/null | head -10

# Same search via Spotlight (faster on large volumes):
mdfind -onlyin ~ -name "*.sh" | head -10

# Find files over 500 MB anywhere on the boot volume:
mdfind "kMDItemFSSize > 524288000" | head -10

# Find files with a specific xattr:
find ~/Downloads -name "*" -type f -print0 2>/dev/null | \
  xargs -0 -I{} sh -c 'xattr -l "{}" 2>/dev/null | grep -q quarantine && echo "{}"' | head -10
```

---

## Pitfalls & Gotchas

1. **`rm -rf` has no undo.** APFS has no "recently deleted" at the filesystem level outside Time Machine. Move to `~/.Trash/` if you want safety. Consider `alias rm='rm -i'` but don't let it make you careless.

2. **`sed -i ''` requires the empty string on BSD.** `sed -i 's/foo/bar/' file` works on GNU; on BSD it expects `sed -i '' 's/foo/bar/' file`. The empty string is the "no backup extension" argument.

3. **`xargs` default delimiter is whitespace.** A filename with a space breaks `find . -name "*.txt" | xargs cat`. Always use `-print0 | xargs -0`.

4. **`cp -c` is APFS-only and silent about it.** On HFS+, exFAT, or network mounts, `cp -c` silently degrades to a regular copy. There's no error. The `-c` flag is a hint, not a requirement.

5. **`ditto` is not `rsync`.** `ditto` copies everything unconditionally. It doesn't do delta sync or comparison. Use rsync for incremental backups; use `ditto` for single correct copies.

6. **openrsync on macOS 15+ is not rsync 3.x.** It's missing some flags. If a backup script breaks after an OS upgrade, this is why. `brew install rsync` restores full rsync 3.x.

7. **`zip` creates `._` AppleDouble trash for xattr-bearing files.** Always use `COPYFILE_DISABLE=1 zip` or `ditto -c -k` when the archive will be opened on non-Mac systems.

8. **`du` double-counts APFS clones.** Two cloned files that share blocks are each reported at full size. `diskutil apfs list` and `diskutil info` show physical usage.

9. **`mdfind` requires Spotlight to be enabled.** `sudo mdutil -s /` checks status. If the volume has indexing disabled (`mdutil -i off /`), `mdfind` returns empty results. On FileVault-locked volumes or recovery environments, the index is unavailable.

10. **`stat` format flags differ from GNU.** macOS: `stat -f "%z"` for size; GNU: `stat -c "%s"`. Writing portable scripts requires detecting which you have: `stat --version 2>/dev/null && GNU || BSD`.

---

## Key Takeaways

- macOS ships BSD userland, not GNU. Flag differences are real and will bite you. Know when to reach for `brew install coreutils`.
- The visible `rwx` mode bits are one layer of a four-layer permission stack: POSIX mode → BSD flags → xattrs → ACLs. `ls -le@` sees all of them.
- `cp -c` is APFS's superpower: zero-copy clones via `clonefile(2)`, instantaneous regardless of file size, CoW divergence on modification.
- `ditto` is the correct tool for Mac-complete copies and archive creation. Plain `zip` and `cp` lose resource forks and produce `._` pollution.
- `/usr/bin/rsync` on macOS 15+ is openrsync, not rsync 3.x. `brew install rsync` for serious use.
- `locate` is gone. Use `mdfind` for Spotlight-backed search, `find` for filesystem traversal.
- `xattr -p com.apple.quarantine` on a downloaded file reveals the originating app and URL — Tier-1 forensic evidence.

---

## Terms Introduced

| Term | Definition |
|------|-----------|
| BSD userland | The set of command-line tools derived from Berkeley Software Distribution; macOS's default, distinct from GNU coreutils |
| clonefile(2) | APFS syscall that creates a CoW clone sharing data blocks with the source |
| Copy-on-Write (CoW) | Storage technique where cloned blocks are shared until modified, then diverge |
| AppleDouble | A format that splits a file's resource fork and xattrs into a companion `._filename` file for non-HFS filesystems |
| Extended attribute (xattr) | Arbitrary key/value metadata attached to a filesystem object's inode, outside the data fork |
| BSD file flag | Immutability/visibility bits stored in `st_flags` (e.g., `uchg`, `hidden`, `nodump`) |
| POSIX ACL | Fine-grained `allow`/`deny` access control entries beyond POSIX mode bits |
| openrsync | Apple's ISC-licensed rsync replacement, shipping in macOS Sequoia 15+; subset of rsync 3.x flags |
| Spotlight store | The `/.Spotlight-V100/` metadata index; queryable via `mdfind`, persists metadata for deleted files |
| APFS birth time | File creation timestamp stored by APFS; survives most copies; accessible via `mdls` or `GetFileInfo` |

---

## Further Reading

- `man clonefile`, `man copyfile`, `man xattr`, `man ditto`, `man hdiutil` — canonical Apple man pages
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — covers file quarantine, Gatekeeper, and xattr-based integrity controls
- Howard Oakley, *The Eclectic Light Company* — regularly covers APFS internals, xattr preservation behavior, and macOS file system quirks; search for "extended attributes" and "APFS clone"
- [openrsync project](https://github.com/kristapsdz/openrsync) — source and flag documentation
- `man find` on macOS vs. `gfind --help` — compare side by side to understand BSD/GNU divergence
- [[02-terminal-shell-basics]] — shell setup, PATH, aliases, dotfiles
- [[04-filesystem-deep-dive]] — APFS volumes, snapshots, firmlinks, synthetic.conf
- [[05-permissions-and-acls]] — deep dive into the full permission stack
- [[09-spotlight-and-metadata]] — `mdfind` predicates, `mdimport`, Spotlight store forensics
