# PurplePeek user manual

PurplePeek helps you **triage media before it ever reaches Photos**. Point it at a folder,
decide each item (keep / skip, favorite, title, caption, keywords, albums), then import the
keepers into your Photos library — or keep-export audio, or delete what you don't want. Your
decisions are saved per file, so you can close the app and come back to a half-triaged folder
without losing a thing.

For *how it's built*, see `DESIGN.md` and `HANDOFF.md`; for *what changed when*, see
`CHANGELOG.md`.

## First run

1. Build + install: `./build-app.sh` (builds `PurplePeek.app`, installs it to `/Applications`,
   and relaunches). macOS 14+.
2. *(Optional but recommended)* install the metadata helpers:
   - `brew install exiftool` — lets PurplePeek embed title/caption/keywords into **photos** on
     import.
   - `pipx install osxphotos` — lets you seed your keyword list from your existing Photos
     library.
   PurplePeek works without these; you just lose those specific conveniences.
3. Launch it and **drop a folder onto the window**, or use **Open Folder** (⌘O) in the toolbar.

The first import (and the first "Re-apply Metadata") will prompt for **Photos access** and a
one-time **"PurplePeek wants to control Photos"** automation prompt — allow both for full
metadata support (see *Why metadata sometimes needs Photos automation* below).

## Scanning a folder

PurplePeek recursively discovers every photo, video, and audio file under the folder you give
it. Classification is by file *type*, not extension, so HEIC/HEIF, ProRes, etc. are recognized
correctly. Hidden files and the insides of packages (`.app`, `.photoslibrary`) are skipped.

- Each scanned folder becomes a **scan root** in the sidebar. Selecting one loads its items.
  See *Organizing the sidebar* below for reordering and custom sections.
- Decisions are stored **by file path**, so re-scanning the same folder never duplicates items
  or wipes your choices — it just adds anything new and refreshes on-disk details.
- **Exclude a top-level subfolder**: Settings → General → *Exclude (top level only)* (default
  `originals`). A folder of that name sitting **directly under** the scan root is skipped whole;
  same-named folders nested deeper are still scanned.

## Organizing the sidebar

By default every scanned folder lives in one **Folders** group. You can reorder and group them:

- **Reorder**: drag a folder up or down to set the order you want — drop it on another folder
  to place it just above that one.
- **Move between sections by dragging**: drag a folder onto another section's **header** (or
  onto any folder already in that section) to move it there. Drag it onto the **Folders**
  header to move it back to the default group.
- **Custom sections**: click the **+** at the top of the sidebar to create a section (e.g.
  "Trips", "To sort"). You can also right-click any folder → **Move to Section ▸** to file it
  (or back to **Folders (default)**); "New Section…" there creates one and moves the folder
  into it in a single step.
- **Manage a section**: use the **⋯** button on a section header (or right-click it) to
  **Rename** or **Delete** it. Deleting a section never touches its folders — they simply fall
  back to the default **Folders** group.
- **Right-click a folder** also offers **Forget Folder** (clears its saved decisions; never
  deletes files on disk).
- The **footer** at the bottom of the sidebar totals your library — e.g. *"12,431 items · 7
  folders"* (items = all photos/videos/audio across every scanned folder).

Your sections, ordering, and assignments are saved in PurplePeek's database, so they survive
restarts and are included in backups.

## The two modes

Switch with the **Browse / Preview** toggle in the toolbar (your default mode is set in
Settings → General).

### Browse mode

A Finder-like **folder tree** (sidebar) + **thumbnail grid** (or list — toggle top-right) +
a per-item **detail panel** on the right.

- Click an item to select it and edit its details (keep/skip, favorite, hidden, title,
  caption, keywords, albums) in the detail panel.
- **Press Space to peek**: with an item selected, hit **Space** to open it full-size in Quick
  Look. Press Space again to close. While the peek is open, clicking another item updates it
  live — just like Finder. (Space types normally when you're editing a title or caption.)
- **Show menu** (top-right): filter the grid by decision — *All / Undecided / Decided / Kept /
  Skipped* — so you can revisit choices, not only triage new items.
- Badges on each thumbnail show its type, your keep (✓) / skip (✕) decision, favorite (♥),
  hidden (eye-slash), and a **missing** marker (orange) if the file has left disk (see
  *Refreshing*).

### Preview mode

A full-size, one-at-a-time walkthrough with an **EXIF panel** — best for fast triage.

| Key | Action |
|-----|--------|
| **Y** | Keep, advance |
| **N** | Skip, advance |
| **U** | Undo last keep/skip |
| **F** | Toggle favorite |
| **H** | Toggle hidden |
| **←/→** | Previous / next |
| **Space** | Quick Look |

- The **Review menu** picks which queue you walk: *Undecided* (default), or *Decided / Kept /
  Skipped / All* to revisit.
- All keys are suspended while a title or caption field has focus, so you can type freely;
  press Return to leave the field and resume keyboard navigation. Moving to another item also
  releases the field automatically, so Y/N work right away on the next item.

**Undo a keep/skip.** Made a wrong call? The **Undo** button (curved-arrow) in the toolbar
reverts your most recent keep/skip — press it repeatedly to step back through several. In
Preview mode you can also press **U** or use the Undo button in the decision bar. (Undo covers
keep/skip; it resets when you switch folders or re-scan.)

## Exact duplicates (decide once)

PurplePeek automatically finds **byte-for-byte identical** files after each scan and groups
them, so you only triage the content once:

- Each set of duplicates shows as a **single item** with a blue **×N** badge (N = number of
  copies). In Preview mode the header shows "N copies".
- Your **keep/skip decision applies to every copy** in the set — decide the one you see, and
  all of them are recorded the same way.
- On **import to Photos, only one copy** of a kept set is imported, so you don't end up with
  duplicates in your library. (The other copies stay on disk with the same decision; use
  **Clean Up → Delete** if you want to remove the redundant files.)
- Detection is by content, so renamed copies are caught and filenames are ignored. It's fast:
  PurplePeek only hashes files that share an exact byte-size with another (a unique size can't
  have a duplicate).
- Turn it off in **Settings → General → "Group exact duplicates"** to see and decide every
  file individually.

## Refreshing (picking up changes on disk)

PurplePeek shows what it found at scan time. If files change on disk afterward:

- **Refresh** (toolbar button, or **⌘R**) re-scans the selected folder in place. New files
  appear; your decisions are preserved.
- Files that were **removed or moved** are flagged **missing** (orange badge) rather than
  silently dropped — your decisions on them survive in case the file comes back, and it
  un-flags automatically if it reappears on a later scan. A file you deleted *through
  PurplePeek* stays "deleted", not "missing". The status toast reports the missing count.
- **Auto-refresh**: turn on Settings → General → **Watch folder for changes** and PurplePeek
  re-scans automatically whenever the selected folder changes on disk (off by default).

## Importing to Photos

Toolbar **Photos → Import to Photos…** opens the import wizard.

- **Filter**: import *all* photos/videos, *keep only*, or *undecided only*. (Audio is never
  imported — see below.)
- Each item's **favorite, hidden, and albums** are applied via PhotoKit. **Title, caption, and
  keywords** are embedded into photos (via `exiftool`) and set on videos afterward (via
  Photos automation).
- The wizard shows live progress and a summary, including any failures.
- Already imported items before setting metadata? **Photos → Re-apply Metadata to Imported
  Items** re-pushes each imported item's current title/caption/keywords to its Photos asset —
  no re-import needed.

### Why metadata sometimes needs Photos automation

macOS only lets apps write four properties directly to a Photos asset (date, location,
favorite, hidden). So PurplePeek uses three paths: favorite/hidden/album go through PhotoKit;
**photo** title/caption/keywords are embedded with `exiftool` *before* import; **video** (and
any photo whose embedding was skipped) title/caption/keywords are set *after* import via Photos
automation — which is why the "control Photos" prompt matters for video metadata. Deny it and
photo metadata still works; video metadata won't.

## Audio: keep-export instead of import

Photos can't hold audio. When you **keep** an audio file, PurplePeek copies it to
`~/Downloads/PurplePeek/Kept Audio/` (configurable in Settings). This happens once per file.

## Deleting files from disk

Toolbar **Clean Up**:

- **Delete Imported Files…** — remove the on-disk copies of items already imported to Photos.
- **Delete Skipped Files…** — remove items you marked Skip.

Both show a confirmation with the count, and you choose **Move to Trash** (recoverable) or
**Delete permanently**. PurplePeek marks the deleted items so they drop out of your working
set.

## Settings

Open Settings from the **gear** button in the toolbar (or press **⌘,**). Three tabs:

- **General** — default mode, appearance (light/dark/system), color theme, top-level exclude
  name, *Watch folder for changes*, and the Kept Audio export folder.
- **Scan Roots** — rename or forget scan roots (forgetting a root removes its saved decisions
  but never touches files on disk), and optional auto-cleanup of roots not scanned in N days.
- **Backup** — see below.

## Backup & restore

PurplePeek automatically backs up its database on launch (zipped, 14-day retention) to
`~/Downloads/PurplePeek backup/`. In Settings → Backup you can change the location/retention,
**Back Up Now**, and see recent backups. This protects your *decisions* (the SQLite database);
your actual media files are never inside these backups.

## Where PurplePeek puts things

| What | Where | Configurable |
|------|-------|--------------|
| Kept audio | `~/Downloads/PurplePeek/Kept Audio/` | Settings → General |
| Auto-backups | `~/Downloads/PurplePeek backup/` | Settings → Backup |
| Decision database | `~/Library/Application Support/PurplePeek/purplepeek.sqlite` | no |

## Troubleshooting

- **Video metadata didn't reach Photos.** The "control Photos" automation prompt was denied.
  Re-enable PurplePeek under System Settings → Privacy & Security → Automation → Photos, then
  use **Photos → Re-apply Metadata to Imported Items**.
- **Photos imported with no title/caption (photos specifically).** Install `exiftool`
  (`brew install exiftool`); without it, photo metadata can't be embedded.
- **Keyword import is greyed out.** Install `osxphotos` (`pipx install osxphotos`).
- **An item shows an orange "missing" badge.** The file left its original location on disk.
  Move it back and Refresh (⌘R), or delete the item if it's gone for good.
- **A folder shows nothing after scanning.** Check the *Show* filter (it may be on Undecided/
  Kept/etc.) and whether your top-level exclude name is hiding the subfolder you expected.
