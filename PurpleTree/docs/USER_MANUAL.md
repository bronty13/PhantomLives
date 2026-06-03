# Purple Tree — User Manual

Purple Tree shows you what's eating your disk space and helps you clean it up
safely. It runs on macOS and Windows.

## 1. Scan a folder

Click **Scan a Folder…** (top bar or the welcome screen) and pick any folder —
your home folder, an external drive, a project directory, anything. Purple Tree
walks the whole tree and adds up the sizes.

While it scans you'll see a live count of files, folders, and bytes, plus the
folder it's currently reading. Click **Cancel** to stop early — you still get
the partial result.

## 2. Explorer

After a scan you land in **Explorer**:

- **Folder tree (left):** click any folder to focus it; expand with the ▸ arrow.
- **Treemap (center):** every rectangle is a folder or file, sized by how much
  space it uses — big blocks are your space hogs. **Click a folder rectangle to
  drill in.** Click a file rectangle to reveal it in Finder/Explorer. Use the
  **breadcrumb** at the top to jump back up.
- **Detail list (bottom):** the current folder's contents. Click a column header
  (**Name / Size / Files / Modified**) to sort. Double-click a folder to open
  it, or a file to reveal it.

To delete: tick the checkboxes in the detail list and click **Delete…**.

## 3. Duplicates

Open **Duplicates** and click **Find Duplicates**. Purple Tree groups files by
size, then hashes them to confirm byte-for-byte matches (fast: it only fully
hashes files that already look identical). Each set keeps the first copy
selected to *keep*; the rest are pre-selected to delete. Adjust the checkboxes,
then **Delete Selected…**.

## 4. Large & Old Files

Open **Large & Old**. Pick a size threshold (e.g. *≥ 100 MB*) and/or an age
(*Not opened in 1 year*) and Purple Tree lists matching files biggest-first.
Great for finding forgotten downloads and stale exports. Select and delete the
ones you don't need.

## 5. Cache Cleanup

Open **Cache Cleanup**. Purple Tree measures known safe-to-clear locations for
your platform (app caches, logs, temp files, build artifacts) and shows how much
each would reclaim. **Nothing is selected by default — you choose.** Tick the
ones you want and click **Move … to Trash**.

Everything here goes to the Trash/Recycle Bin, never permanently deleted. Quit
the related apps first so their caches aren't in use.

## 6. Export & Snapshots

- **Export ▾** (top bar) saves the scan as **CSV**, **HTML**, or **JSON** —
  reports default to `~/Downloads/Purple Tree/` (or your Downloads on Windows).
- **Save Snapshot** stores the scan so you can reload it later and compare.

## 7. Deleting safely

By default **everything goes to the Trash / Recycle Bin** and can be restored.

To enable permanent deletion, open **Settings → General → Enable permanent
delete**. Even then, the delete dialog requires a separate confirmation, and
Purple Tree always refuses to delete filesystem roots, system folders, your home
folder, and its own data — no matter what.

## 8. Backups (Settings → Backup)

Purple Tree backs up its own settings and saved snapshots automatically on
launch, to `~/Downloads/Purple Tree backup/`. In **Settings → Backup** you can:

- turn auto-backup on/off and choose the folder,
- set how many days to keep backups (0 = keep forever),
- **Run Backup Now**, **Test** an archive, or **Restore** one (a safety backup
  is taken first).

## Tips & limits

- **macOS:** scanning a folder you pick works right away. To scan `~/Library`,
  another user's folder, or your whole drive, grant Purple Tree **Full Disk
  Access** in System Settings → Privacy & Security, then rescan. Locations it
  can't read are skipped and counted (shown as "skipped").
- **Symlinks** are listed but not followed (so totals stay honest and scans
  can't loop).
- **Hard links** are de-duplicated in folder totals on macOS; on Windows they're
  counted once per entry.
