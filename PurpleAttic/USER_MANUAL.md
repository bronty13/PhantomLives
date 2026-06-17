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
- *(Optional)* **`restic`** (`brew install restic`) for an encrypted, unattended
  off-site copy to Backblaze B2 (see "Off-site backup" below). No Cryptomator,
  no macFUSE, no manual unlock.

### Grant the three permissions (required — the app blocks runs without them)

PurpleAttic won't let you Dry Run or Archive until **all three** macOS grants are
in place. The **Archive pane shows a Permissions panel** with a row per grant and
*Grant…* / *Settings…* buttons:

1. **Full Disk Access** — so osxphotos can read inside the protected Photos
   library. Add **PurpleAttic** in **System Settings → Privacy & Security → Full
   Disk Access** (the panel's *Settings…* button opens it). **This grant is
   per-binary:** if you'll use the scheduler, you must *also* add the bundled tool
   at `PurpleAttic.app/Contents/MacOS/pattic` — the app's own grant does not cover
   it. The **Schedule pane** has *Reveal pattic in Finder* + *Open Full Disk
   Access…* buttons so you can drag it straight into the list. Skip this and macOS
   pops *"PurpleAttic would like to access data from other apps"* every time the
   scheduled run fires.
2. **Photos Automation** — lets the archive drive Photos.app to download/export
   images. Click **Grant…** and approve *"PurpleAttic wants to control Photos."*
   *Skip this and osxphotos thrashes — "AppleScript export failed 10 consecutive
   times, restarting Photos app" — and stalls.*
3. **Photos Library** — PhotoKit access used by the guarded purge. Click
   **Grant…** and Allow.

After granting, each row turns to a green check and the run buttons enable. (A
new grant sometimes needs the app relaunched to register.)

---

## 2. First run (on the originals Mac)

1. **Open PurpleAttic.** The sidebar has five panes: **Archive, Schedule,
   Settings, Backup, Purge**. The bottom of the sidebar shows green checks for
   osxphotos / exiftool / rsync — fix any red one before continuing.

2. **Settings → Destinations.**
   - **Primary archive drive (disk 1):** choose your big drive's *root*, e.g.
     `/Volumes/Vortex4TB`.
   - **Archive subfolder:** defaults to **"Photos Archive"**. The archive is
     nested here so the drive root stays tidy — originals land at
     `/Volumes/Vortex4TB/Photos Archive/originals` (the screen shows the composed
     path). Leave it as-is unless you want a different folder; set it empty to
     write at the drive root.
   - **Mirror drive (disk 2):** add your second drive's root, e.g.
     `/Volumes/Mirror2TB`. The same subfolder is used. *(A mirror is required
     before purge — it's the second copy verification depends on.)*
   - **Off-site backup (optional):** the encrypted off-site copy is now driven by
     **`restic`** to a pluggable list of destinations (Backblaze B2 today). It runs
     unattended and skips cleanly when you're offline. Setting it up is a one-time
     guided step (bucket + Keychain creds + a written-down recovery passphrase) —
     see **"Off-site backup (restic → Backblaze B2)"** further below. *(The old
     Cryptomator vault is retired.)*
   - Leave **"Download missing originals from iCloud"** OFF on this Mac (you
     already have the originals). Click **Save**.

   - Leave **"Skip 'Shared with You' & shared-album items"** ON (the default).
     Photos other people shared with you (via Messages or a shared album) aren't
     your originals and have no full-resolution master to archive — with this off
     they show up forever as bogus *"missing"* photos you can never download. Your
     own iCloud **Shared Library** photos are unaffected.

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

   If the Archive pane shows an orange **"Possible low free space"** warning,
   sanity-check that drive — it's a rough estimate from your library's originals
   size and won't block the run, but it's worth a look before a multi-hour
   archive.

6. **Archive → Run Archive.** A **progress bar across the top** shows the phase
   stepper — **Export HEIC → Export JPEG → Mirror → Verify → Cloud** — with the
   active phase highlighted, its elapsed time, the current file being copied, and
   a live count of files written. (The detailed log scrolls below it.) The first
   run pulls every original to disk — **expect hours; let it run.** A readable
   report lands in `~/Downloads/PurpleAttic/`. A handful of old scans show up as
   *"N sidecar-only"* — harmless: the image **and** its `.xmp` sidecar are
   archived; only the in-file metadata re-embed was skipped (damaged EXIF). The
   report lists them. If a **mirror drive isn't mounted**, that mirror is **skipped
   with a warning** (never written to the boot disk) — mount it and re-run.

7. **Confirm it landed.** Open `/Volumes/Vortex4TB/Photos Archive/originals/<year>/…`
   in Finder — you'll see dated folders of originals with `.xmp` sidecars next to
   them, plus a parallel `jpeg/` tree.

That's the whole safe workflow. **At this point you already own a complete,
portable, triple-stored copy of your library — independent of Apple — without
deleting anything.**

---

## 3. Keep it in sync

Re-running **Run Archive** is incremental (osxphotos `--update`): only new or
changed photos are copied. You can do that by hand, or automate it:

**New-photo review.** On these incremental runs, PurpleAttic also copies the
*newly-added* photos (originals + JPEG) into a dated batch under **`~/Downloads/
PurpleAttic/NEW PHOTOS TO REVIEW/`** — so you have just-the-new-stuff in one place
to hand off to someone (to keep) or delete after a look, without disturbing the
archive. It's **on by default** (Settings → New-photo review, where you can change
the folder or turn it off) and is **skipped on the first/baseline run** (when
everything is "new"). Each run's batch is its own timestamped folder; delete a
batch once you've reviewed it.


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
| New items to review (per run) | `~/Downloads/PurpleAttic/NEW PHOTOS TO REVIEW/<timestamp>/` (configurable) |
| Detailed logs | `~/Library/Logs/PurpleAttic/` |
| Scheduler logs | `~/Library/Logs/PurpleAttic/scheduler.*.log` |
| Profile + settings | `~/Library/Application Support/PurpleAttic/` |
| Config backups | `~/Downloads/PurpleAttic backup/` |
| Your archive | wherever you set Primary / Mirror |
| Off-site (restic) | the restic repo you configure (e.g. a Backblaze B2 bucket) |
| Off-site secrets | macOS **Keychain** (restic passphrase, B2 key) — never on disk in the clear |

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **"Primary destination is still the placeholder…"** banner; buttons disabled | You haven't set real paths. Settings → Destinations → choose your drive → Save. |
| **"Optimize Storage likely … INCOMPLETE"** warning | This Mac doesn't have all originals. Run on the Mac set to "Download Originals," or (last resort) enable "Download missing originals" in Settings. |
| **"Primary destination isn't available (is the drive mounted?)"** | The external drive isn't connected/mounted. Plug it in. |
| Run buttons **disabled** with a red **Permissions** panel | One or more of Full Disk Access / Photos Automation / Photos Library isn't granted — use the panel's **Grant…** / **Settings…** buttons (§1). All three are required. |
| Log floods with **"AppleScript export failed … restarting Photos app"** or **"AppleScript timed out: retrying killall"**, and Photos keeps getting killed | You're on the **AppleScript** download path. Leave **"Use PhotoKit to download"** ON (Settings → Source, the default) — PhotoKit fetches missing originals without driving or killing Photos. The AppleScript path is unreliable on slow/indeterminate iCloud items. |
| Orange **"Possible low free space"** warning | Estimate says a destination drive may be tight (or isn't mounted). Advisory only — verify the drive; the archive may still fit. |
| **osxphotos** shows red in the footer | `brew install pipx && pipx install osxphotos`, then reopen the app. |
| Off-site step says **"skipped — offline"** / **"repo unreachable"** | Normal on a laptop with no network — the off-site backup catches up on the next run with internet. Archiving never blocks on it. |
| Off-site step says **"B2 credentials not in Keychain"** | The restic passphrase / B2 key aren't stored yet. Follow "Off-site backup (restic → Backblaze B2)" below to add them. |
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

---

## 9. Off-site backup (restic → Backblaze B2)

The third copy is an **end-to-end-encrypted, unattended** backup made with
[`restic`](https://restic.net). Your cloud provider only ever stores ciphertext;
the keys live on your Mac. It is **resumable**, **deduplicated**, **snapshotted**
(nothing is ever overwritten/lost), and **integrity-checked** (`restic check`).
Each off-site destination is independent and **skips cleanly when you're offline**,
so a laptop with no drives/network is a clean no-op that catches up later.

The off-site layer is a **pluggable list** of destinations: Backblaze **B2** is
supported today; an rclone-backed remote (Dropbox / Proton Drive / S3 / rsync.net)
is config-only to add later — no app change.

### Set it up in the app — no Terminal needed (the **Off-site** tab)

Everything below is now point-and-click in PurpleAttic's **Off-site** tab. (The
manual CLI equivalent is kept further down for power users / scripted hosts.)

1. **Install restic:** `brew install restic` (the one prerequisite that isn't in-app).
2. **Backblaze B2 (web console):** create a **private bucket** and an **application
   key** scoped to just that bucket. Copy the keyID and application key (the key is
   shown once).
3. **Off-site tab → Destination:** if no destination exists, click **Add Backblaze
   B2 destination**, then fill in the **bucket** name (and optionally the path within
   it — defaults to `photos`). Turn **Enabled** on.
4. **Off-site tab → Credentials:** paste the **B2 key ID** and **application key** and
   click **Save to Keychain**. On a brand-new repository the app also generates and
   stores the **runtime passphrase** for you (it lives only in the Keychain). The
   three rows flip to green ✓ when stored. *(Don't regenerate the runtime passphrase
   for a repo that already has backups — it must match what the repo was created with.)*
5. **Off-site tab → Repository status:** click **Refresh**. Once your first backup has
   run it shows the snapshot count, the latest snapshot time, and the key count.
6. **Off-site tab → Recovery key → Set up recovery key:** a guided sheet **generates**
   a strong word-based passphrase (or type your own), you **write it on paper for your
   safe** and tick the confirmation, then **Add recovery key to repository**. The app
   immediately walks you through the drill (next section).

### Prove the recovery key BEFORE you rely on it (built into the app)

A backup you can't restore is worthless, and a recovery key you've never tested is a
guess. Right after adding the key, the recovery sheet asks you to **re-type the
passphrase from your paper** and runs a **Keychain-bypassed restore drill**: it opens
the repo using *only* the typed passphrase and byte-compares a restored sample to your
local archive. A green **PASS** proves the paper copy alone can recover everything.
Re-run this drill (the **Add another recovery key** button leads to the same verify
step) after any key change, and only decommission an older off-site copy once it
passes.

### Manual CLI setup (advanced / headless hosts)

The in-app flow above is the recommended path. If you prefer the command line (or are
configuring a host without the GUI), the equivalents are:

```sh
# 1. Store the secrets (service name must match the destination's keychainService):
SVC="PurpleAttic Restic B2"
security add-generic-password -U -s "$SVC" -a restic-password -w '[RUNTIME PASSPHRASE]'
security add-generic-password -U -s "$SVC" -a b2-account-id   -w '[B2 KEY ID]'
security add-generic-password -U -s "$SVC" -a b2-account-key  -w '[B2 APPLICATION KEY]'
```
```json
// 2. Add the destination to profile.json → cloudDestinations:
"cloudDestinations": [
  { "name": "Backblaze B2", "kind": "resticB2", "enabled": true,
    "repo": "b2:your-bucket-name:photos",
    "keychainService": "PurpleAttic Restic B2", "checkAfterBackup": true }
]
```
```sh
# 3. After the first backup initializes the repo, add the recovery key:
restic key add        # prompts for the NEW (recovery) passphrase
# 4. Recovery drill — Keychain bypassed, recovery passphrase only:
export RESTIC_REPOSITORY='b2:your-bucket-name:photos'
export B2_ACCOUNT_ID='[B2 KEY ID]'  B2_ACCOUNT_KEY='[B2 APPLICATION KEY]'
export RESTIC_PASSWORD='[RECOVERY PASSPHRASE]'    # NOT the Keychain
restic snapshots
restic restore latest --target /tmp/attic-recovery-test --include '[some subfolder]'
diff -r "/Volumes/ROG_WHITE/Photos Archive/[same subfolder]" \
        "/tmp/attic-recovery-test/Volumes/ROG_WHITE/Photos Archive/[same subfolder]"
```

### Day-to-day

Nothing — the scheduled archive backs up to B2 automatically after the local
mirror+verify, and **PurpleMirror** shows the "Photo Archive" job's status (off-site
result included). Manual integrity check any time:
```sh
restic -r 'b2:your-bucket-name:photos' check                       # structure
restic -r 'b2:your-bucket-name:photos' check --read-data-subset 1/20  # sampled data
```
