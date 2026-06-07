# Purple Archive — User Manual

Purple Archive is a macOS-native archive utility: a SwiftUI app **and** a
command-line tool (`parc`) that share one engine. It opens and creates virtually
every archive format — modern and vintage — fixes the cross-platform problems
other tools fumble, and integrates directly into Finder.

---

## Contents

1. [Supported formats](#supported-formats)
2. [The app](#the-app)
   - [Browsing an archive](#browsing-an-archive)
   - [Extracting](#extracting)
   - [Compressing](#compressing)
   - [In-place editing](#in-place-editing)
   - [Fixing garbled filenames (encoding)](#fixing-garbled-filenames-encoding)
   - [Encrypted archives & the password vault](#encrypted-archives--the-password-vault)
   - [Settings](#settings)
3. [Finder integration](#finder-integration)
4. [The `parc` command line](#the-parc-command-line)
5. [Where files go](#where-files-go)
6. [Updating](#updating)

---

## Supported formats

**Read & create:** ZIP (incl. ZIP64, AES-256), 7z, TAR, TAR+gzip/bzip2/xz/zstd,
gzip, zstd.

**Read (extract/browse):** everything above plus RAR & RAR5, CAB, ISO 9660,
CPIO, AR/DEB, XAR, LHA/LZH, WARC, and the **legacy Macintosh formats** —
**StuffIt** (`.sit`, including the Arsenic method), **Compact Pro** (`.cpt`),
**BinHex** (`.hqx`), and **MacBinary** (`.bin`) — including nested wraps like
`.sit.hqx`.

If a format can't be created (e.g. RAR, the legacy Mac formats), Purple Archive
still opens it; just extract and re-create in a modern format.

---

## The app

The window has a sidebar with **Browse** and **Compress**, a content area, and a
status bar. You can drag anything onto the window at any time: drop **an archive**
to browse it, drop **files/folders** to compress them.

### Browsing an archive

Open an archive any of these ways:

- Drag it onto the window.
- **File ▸ Open Archive…**, or ⌘O.
- In Finder, right-click the archive ▸ **Open With ▸ Purple Archive** (or set
  Purple Archive as the default and double-click).

The contents appear as a **folder tree** — name, size, modified date, and a 🔒 on
encrypted entries. Folders show a disclosure triangle and an item count; click it
to expand the folder and see its contents, any number of levels deep. The header
shows the file count and total uncompressed size.

### Previewing a file (Quick Look)

To peek inside the archive without extracting, select a file entry and either:

- click the **eye** button in the browser header, or
- press **Space**, or
- right-click the entry ▸ **Quick Look**.

A preview sheet opens with the same rich rendering Finder's spacebar Quick Look
gives you — text, images, PDFs, audio/video, code, CSV, and more. Only that one
file is streamed out (a temporary copy), so even a huge archive previews
instantly. **Reveal** shows the temp copy in Finder; **Done** closes the sheet.

### Extracting

**Select the files you want** the same way you do in Finder: click a row,
**⌘-click** to add or remove individual rows, **⇧-click** for a range, ⌘A for
all. (Note: on macOS *Control*-click is a right-click, not multi-select — use
**Command (⌘)**.) The header shows how many are selected.

The primary **Extract All… / Extract N Selected…** button opens a folder chooser
so you can see and confirm where files go before extracting — pick a folder and
the selected items (or everything, if nothing is selected) are written there,
keeping their folder structure. Selecting a folder pulls out everything inside
it. The folder you pick becomes the destination for the rest of the session.

For a quicker path, the **⌄ menu** beside the button skips the chooser:

- **Extract to <folder>** — extract straight to the current default.
- **Extract All Items to <folder>** — extract everything, ignoring the selection.
- **Set Default Destination…** — change the default folder (sticky for the
  session; reverts to the **Settings** default on relaunch).

Right-click any item ▸ **Extract Here / Extract to Folder…** does the same, and
shows the destination right in the menu. Encrypted archives prompt for a password
first — tick the **eye** to reveal what you typed.

### Testing an archive

Click **Test** in the browser header to verify the archive's integrity — Purple
Archive reads every entry (checking CRCs and decompression) without writing
anything to disk, and reports "intact" or "failed" in the status bar. Handy
before trusting or deleting an original.

### Compressing

Switch to **Compress** (or drop files on the window):

1. Choose a **Format**. Not sure? Click **Recommend** — Purple Archive suggests
   the best one for your files (e.g. ZIP for sharing to Windows, TAR+zstd for the
   best speed/size balance, or a fast "store" path when your files are already
   compressed like photos/video).
2. Optionally set a **password** (ZIP → AES-256). When you do, a **Confirm** box
   appears — re-type the password until the indicator turns green (Create stays
   disabled while they differ, so a typo can't lock you out of your own
   archive). Use the **eye** toggle to reveal what you typed. Toggle
   **Windows-safe** to sanitize names that Windows would reject.
3. Click **Create Archive**. A save dialog opens, pre-filled with a suggested
   name and the default location (`~/Downloads/PurpleArchive/`) — rename it,
   choose a different folder, or just click **Create**.

`.DS_Store` and `__MACOSX` junk is stripped automatically.

### In-place editing

While browsing a writable archive (ZIP/7z/TAR-family) you can change it without
manually unpacking and repacking:

- **Add files** — the **＋** button in the header.
- **Delete** — select rows and click 🗑, or right-click ▸ Delete.
- **Rename** — right-click a single entry ▸ Rename…

Purple Archive rebuilds the archive in the same format, preserving every
untouched file's contents, permissions, and dates, then atomically replaces the
original.

### Fixing garbled filenames (encoding)

Archives made on Windows or Linux often store filenames in a legacy code page
with no UTF-8 marker, so other Mac tools show mojibake like `æ–‡å­—`. Purple
Archive auto-detects the right encoding when you open an archive (you'll see it
noted in the status bar). If a name still looks wrong, use the **encoding menu**
in the browser header to switch among UTF-8, Shift-JIS, GBK, EUC-KR, Big5,
Windows-1251, CP437, and more — the listing re-decodes instantly, no
re-extraction.

### Encrypted archives & the password vault

Enter a password once and let Purple Archive remember it in your **Keychain**:
tick **Remember in Keychain** in the password prompt. Next time you extract that
archive, the password is filled in automatically.

### Settings

- **General** — default create format & level, strip-Mac-metadata, and the
  extract destination folder.
- **Backup** — Purple Archive backs up its own settings/recents on launch to
  `~/Downloads/PurpleArchive backup/` (14-day retention). Toggle it, change the
  folder/retention, **Back Up Now**, and browse recent backups here.

---

## Finder integration

- **Quick Look** — select an archive in Finder and press **Space** to see a
  styled listing of its contents (no extraction). Works for ZIP/7z/TAR/RAR and
  the legacy Mac formats.
- **Thumbnails** — archives get a purple icon badged with their file count.
- **Right-click menu** — **Purple Archive ▸ Extract Here / Compress to ZIP /
  TAR.ZST / 7z** on any selection.

First time: enable these in **System Settings ▸ Login Items & Extensions ▸ Quick
Look** and **Finder** (toggle Purple Archive). If a preview looks stale, run
`qlmanage -r` in Terminal.

---

## The `parc` command line

`parc` is the same engine on the command line — one tool for every format. Install
it to your PATH by symlinking the copy inside the app bundle:

```sh
ln -s "/Applications/PurpleArchive.app/Contents/Helpers/parc" /usr/local/bin/parc
```

### Commands

```sh
parc l  <archive> [--json] [--encoding auto|utf8|cp437|shift-jis|gbk|euc-kr|big5|cp1251|cp1252]
parc x  <archive> [-o dir] [-p password] [--use-vault] [--skip-existing]
parc a  <out.zip|out.tar.zst|out.7z|…> <files…> [-l level] [-p password] [--windows-safe] [--threads N]
parc t  <archive> [-p password]                  # verify integrity
parc info <archive>                              # entries, size, ratio, encryption
parc hash <file> [--algo md5|sha1|sha256|sha512]
parc convert <in> <out.fmt> [-p password] [-l level] [--windows-safe]
parc edit <archive> [--delete path …] [--rename old=new …] [--add local=path …] [-p password]
parc repair <archive> [-o dir] [-p password]     # salvage a damaged/truncated archive
parc recommend <files…> [--windows] [--encrypted] [--max-compression]
parc vault list | forget <key>                   # Keychain password vault
parc versions
```

### Examples

```sh
parc a backup.tar.zst ~/Documents --level 19        # fast, high-ratio, multicore
parc a secret.zip report.pdf -p hunter2             # AES-256 encrypted
parc x download.sit.hqx -o ~/old-mac-stuff          # legacy formats just work
parc l photos.zip --encoding shift-jis              # fix Japanese filenames
parc convert legacy.rar modern.tar.zst              # transcode in one step
parc edit release.zip --delete debug.log --add NOTES.txt=README.txt
parc recommend ~/Movies --max-compression
```

---

## Where files go

- **Extractions & created archives:** `~/Downloads/PurpleArchive/` (override in
  Settings; the choice persists).
- **App backups:** `~/Downloads/PurpleArchive backup/`.
- **Internal settings/cache:** `~/Library/Application Support/PurpleArchive/`.

---

## Updating

Purple Archive checks for updates automatically (Sparkle) and you can trigger a
check from the app menu (**Check for Updates…**). Updates are notarized and
EdDSA-signed.
