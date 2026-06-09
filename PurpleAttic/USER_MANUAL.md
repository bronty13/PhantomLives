# PurpleAttic — User Manual

PurpleAttic copies your **Photos** library out to ordinary files you control,
keeps several **verified** copies, and (only when you choose) **removes** old,
un-flagged photos from Photos so your library stays small. The archive is plain
files in dated folders — openable by any app, forever — so you never get trapped
the way old iPhoto/`.photoslibrary` bundles trap people.

> **Golden rule:** archiving is always safe and reversible. *Purging* deletes
> from Photos (and therefore every device). PurpleAttic only ever purges a photo
> after it has proven that photo is sitting in **two** of your archive copies —
> and even then it asks you twice. Purge ships **OFF**.

---

## 1. What you need

- The Mac that holds your **full-resolution originals** — i.e. Photos →
  Settings → iCloud set to **"Download Originals to this Mac"**, and the download
  finished. *(A Mac on "Optimize Mac Storage" only has previews; PurpleAttic will
  detect that and refuse to make an incomplete archive.)*
- Two drives for the on-disk copies (e.g. a 4 TB primary + a 2 TB mirror).
- `osxphotos` and `exiftool` installed:
  ```
  pipx install osxphotos      # or: brew install osxphotos
  brew install exiftool
  ```
  (`rsync` already ships with macOS.)
- *(Optional)* **Cryptomator** + an unlocked vault, for an encrypted cloud copy.

### Grant Full Disk Access

osxphotos needs to read inside the Photos library, which macOS protects. Open
**System Settings → Privacy & Security → Full Disk Access** and add
**PurpleAttic** (and, if you'll use the scheduler, the bundled tool at
`PurpleAttic.app/Contents/MacOS/pattic`). If a run fails with a *permissions*
error, this is almost always why.

---

## 2. First run (on the originals Mac)

1. **Open PurpleAttic.** The sidebar has five panes: **Archive, Schedule,
   Settings, Backup, Purge**. The bottom of the sidebar shows green checks for
   osxphotos / exiftool / rsync — fix any red one before continuing.

2. **Settings → Destinations.**
   - **Primary archive (disk 1):** choose your big drive, e.g.
     `/Volumes/Vortex4TB/PhotoArchive`.
   - **Mirror (disk 2):** add your second drive, e.g.
     `/Volumes/Mirror2TB/PhotoArchive`. *(A mirror is required before purge —
     it's the second copy verification depends on.)*
   - **Cloud vault (optional):** if you use Cryptomator, unlock the vault and
     point this at its mounted path; the line below shows **Unlocked — ready** in
     green when it's set.
   - Leave **"Download missing originals from iCloud"** OFF on this Mac (you
     already have the originals). Click **Save**.

3. **Settings → Formats.** Keep both **HEIC originals** (full fidelity) and
   **JPEG derivatives** (universally openable) ticked.

4. **Settings → Retention.** Set the **keep window** (default 365 days) and the
   keep flags — by default a **"Save" album** and a **`save` keyword** pin a
   photo forever. (Optionally also keep Favorites.) These only matter for purge
   later; setting them now is fine.

5. **Archive → Dry Run.** This previews the osxphotos pass without writing
   anything. The Archive header should show a green-ish library line ("… originals
   on disk — looks fully downloaded"). If it instead warns **"Optimize Storage
   likely … INCOMPLETE,"** stop — you're on the wrong Mac or the download hasn't
   finished.

6. **Archive → Run Archive.** Watch the live log: HEIC export, JPEG export, the
   rsync mirror, the verify step, then the cloud copy (if the vault is unlocked).
   The first run pulls every original to disk — **expect hours; let it run.** A
   readable report lands in `~/Downloads/PurpleAttic/`.

7. **Confirm it landed.** Open `/Volumes/Vortex4TB/PhotoArchive/originals/<year>/…`
   in Finder — you'll see dated folders of originals with `.xmp` sidecars next to
   them, plus a parallel `jpeg/` tree.

That's the whole safe workflow. **At this point you already own a complete,
portable, triple-stored copy of your library — independent of Apple — without
deleting anything.**

---

## 3. Keep it in sync

Re-running **Run Archive** is incremental (osxphotos `--update`): only new or
changed photos are copied. You can do that by hand, or automate it:

**Schedule pane** → turn on **Run the archive automatically**, pick **Daily** or
**Weekly** and a time (a quiet hour like 2:00 AM is good), then **Apply**. Status
shows **Loaded**, the next run, and the last run; **Run Now** fires it on demand
and **Reveal Log** opens the scheduler log.

Notes:
- The schedule runs only on **this** Mac and only while it's **awake**.
- It runs the **archive only** — it can *never* purge.
- The background run needs Full Disk Access on the bundled `pattic` (see §1).

---

## 4. Backups (of the app's own settings)

PurpleAttic backs up its **configuration** (profiles + settings) on launch to
`~/Downloads/PurpleAttic backup/` (14-day retention). The **Backup** pane lets
you change the folder/retention, **Run Backup Now**, and reveal past backups.
*(This protects your setup — the photo archive itself is protected by the 3-copy
strategy above, not this zip.)*

---

## 5. Purging — only when you're ready

Purging removes aged, un-pinned photos from Photos to shrink your live library.
**Do this only after you've run the archive for a while and trust it** — and
only on the Mac with the complete archive.

1. **Purge → Preview Eligible Photos** (always safe, deletes nothing). You'll see:
   - **Eligible** — old enough and not pinned.
   - **Verified in ≥2 copies — deletable** — present + size-matched in your
     primary *and* a mirror. **Only these can ever be deleted.**
   - **Unverified — skipped** — not in both copies yet (often because the archive
     is incomplete). These are never touched.
   - Plus space freed, date range, and a sample list.
2. Want to protect something? Add it to your **"Save" album** (or tag it `save`),
   then **Preview** again — it drops out of "eligible."
3. When the numbers look right: **Purge → Enable** (confirm), then **Delete N
   Verified Photos…** → confirm in-app → **macOS asks once more** → done. Deleted
   photos go to Photos' **Recently Deleted (30 days)** and disappear from all your
   devices.

> **Don't enable purge on a Mac with only a partial archive** (e.g. a laptop on
> Optimize Storage, or against a throwaway test archive). Preview there all you
> like; just don't delete.

---

## 6. Where things live

| Thing | Location |
|---|---|
| Run reports (human-readable) | `~/Downloads/PurpleAttic/report-*.txt` |
| Detailed logs | `~/Library/Logs/PurpleAttic/` |
| Scheduler logs | `~/Library/Logs/PurpleAttic/scheduler.*.log` |
| Profile + settings | `~/Library/Application Support/PurpleAttic/` |
| Config backups | `~/Downloads/PurpleAttic backup/` |
| Your archive | wherever you set Primary / Mirror / Vault |

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **"Primary destination is still the placeholder…"** banner; buttons disabled | You haven't set real paths. Settings → Destinations → choose your drive → Save. |
| **"Optimize Storage likely … INCOMPLETE"** warning | This Mac doesn't have all originals. Run on the Mac set to "Download Originals," or (last resort) enable "Download missing originals" in Settings. |
| **"Primary destination isn't available (is the drive mounted?)"** | The external drive isn't connected/mounted. Plug it in. |
| A run errors with a **permissions** message | Grant Full Disk Access to PurpleAttic (and `pattic`) — §1. |
| **osxphotos** shows red in the footer | `pipx install osxphotos`, then reopen the app. |
| Cloud step says **"vault not mounted"** | Unlock the Cryptomator vault; the cloud copy catches up next run. Archiving never blocks on it. |
| Scheduled run didn't happen | The Mac was asleep at the scheduled time, or `pattic` lacks Full Disk Access. Check the scheduler log (Schedule → Reveal Log). |
| Purge shows lots of **Unverified** | Those photos aren't in both archive copies — usually the archive is incomplete on this Mac. Finish a full archive on the originals Mac first. |

---

## 8. The `pattic` command line (optional)

The same engine ships as a CLI inside the app, for scripting the **archive**
(it has no purge command):

```
BIN=/Applications/PurpleAttic.app/Contents/MacOS/pattic
$BIN doctor                 # check the toolchain
$BIN init                   # write a starter profile to edit
$BIN plan                   # print the osxphotos commands (runs nothing)
$BIN export --dry-run       # plan-only, no writes
$BIN export                 # archive: export → mirror → verify → cloud
$BIN export --deep          # verify with SHA-256 (slow, thorough)
```

Profiles live at `~/Library/Application Support/PurpleAttic/profile.json`
(override with `--profile`).
