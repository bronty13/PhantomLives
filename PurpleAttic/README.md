# PurpleAttic

Export your macOS **Photos** library to a plain-file archive you control, keep
multiple **verified** copies (2 on disk + 1 encrypted in the cloud), and — once
you're ready, behind a deliberate guard — **purge** aged, un-pinned photos from
Photos so your live library stays small and browsable.

The whole design is built to avoid the trap of legacy iPhoto/`.photoslibrary`
bundles that become unopenable years later: the archive is **ordinary files in
dated folders, with metadata embedded and in XMP sidecars**, openable by any
image viewer forever.

> **Status: 0.15.0 — the purge now rides out a busy iCloud library instead of failing:
> a `PHPhotosErrorDomain 3300` (Photos rejecting *every* asset-mutation while it digests a big
> sync backlog) is treated as "library busy", so PurpleAttic **pauses on the stuck batch with
> escalating back-off and auto-resumes the instant Photos accepts the change** — pacing the purge
> to iCloud's own throughput, reporting `done/total (%)` + the next retry, leave-it-running
> unattended, with a **Cancel** button and a determinate progress bar; also fixes case-sensitive
> UUID resolution (`fetchAssets(withLocalIdentifiers:)` needs the uppercase UUID). Prior 0.14.0 —
> adds "Stage to 'To Delete' album", the scalable purge path:
> PurpleAttic stages the verified-deletable photos into an album with no prompts, then you
> delete them once inside Photos.app (Apple's engine paces the iCloud sync) — avoiding both
> the per-batch macOS confirmation and the `PHPhotosErrorDomain 3300` choke that break direct
> deletion at scale; direct delete remains for small sets; resilient batches + retry-backoff
> on direct delete; fixes the purge ≥2-copy verification that rejected ~all photos
> (it matched the pre-export Photos size, but `--exiftool` enlarges archived files; now
> verifies by filename + primary↔mirror byte-consistency); fixes the purge preview crashing
> on osxphotos' non-standard JSON (`Infinity`/`NaN` literals); excludes "Shared with You" + shared-album items from the
> export (`excludeSharedAndSyndicated`, on by default) so non-owned content with
> no master stops showing as bogus "missing" originals; `--download-missing` uses
> the reliable PhotoKit path (`usePhotoKitForDownload`, on by default) instead of
> the AppleScript one that times out and kills Photos; plus "NEW PHOTOS TO REVIEW"
> staging of each incremental run's new items (on by default); full pipeline
> validated end-to-end, with a live progress dashboard, graceful error handling,
> and a mount guard:** engine + `pattic` CLI
> + `PurpleAttic.app` GUI, with the permissions preflight, "Photos Archive"
> subfolder, free-space check, previews-only guard, Cryptomator vault status,
> guarded purge, and launchd scheduler. The Archive pane shows a phase stepper
> (Export → Mirror → Verify → Cloud) with per-phase progress; a run won't start
> until Full Disk Access, Photos Automation, and Photos Library are all granted.
> Purge ships **disabled** (`purgeEnabled` off) and deletes only photos verified
> in ≥2 archive copies, behind two confirmations. The scheduler archives only —
> never purges. The CLI never deletes.

**Docs:** step-by-step usage is in **[USER_MANUAL.md](USER_MANUAL.md)** (Vortex
first-run, the purge workflow, troubleshooting); the architecture/dev snapshot is
in **[HANDOFF.md](HANDOFF.md)**.

## How it works

```
Photos library ──osxphotos──▶ Primary archive ──rsync──▶ Mirror (2nd disk)
   (originals)                 HEIC + JPEG          │
                                                    └──restic──▶ Off-site repo(s)
                                                                 (E2EE, e.g. Backblaze B2)
```

1. **Export** — `osxphotos` writes two trees under the primary archive:
   `originals/` (untouched HEIC/RAW, full fidelity) and `jpeg/` (a
   universally-openable JPEG set). Both incremental (`--update`), both with
   metadata embedded (`--exiftool`) **and** in `.xmp` sidecars.
2. **Mirror** — `rsync` (no `--delete`) replicates the primary to a second
   physical disk.
3. **Verify** — every mirror is compared against the primary (path + size; deep
   SHA-256 optional). This is the evidence the future purge stage requires
   before it will delete anything.
4. **Off-site (restic)** — the primary is backed up with **`restic`** to a
   **pluggable list** of client-side-encrypted destinations (Backblaze **B2**
   today; an rclone-backed Dropbox/Proton/S3/rsync.net remote is config-only
   later). The provider only ever sees ciphertext; backups are deduplicated,
   snapshotted ("nothing ever lost"), resumable, and verified with `restic
   check`. Each destination is independent and **skips cleanly when offline**
   (a laptop with no network is a clean no-op that catches up next run) — so
   archival never blocks on it. No macFUSE, no manual unlock, no iCloud
   eviction. *(The earlier Cryptomator/macFUSE → iCloud Drive vault is retired;
   `cloudVaultPath` remains decodable but is ignored.)*

   The runtime restic passphrase + B2 key live in the **macOS Keychain**
   (non-interactive). A separate **recovery passphrase** (written down for a
   physical safe) makes the archive recoverable even if the Mac and its Keychain
   are gone. All of this is configured **in the app's Off-site tab — no Terminal**:
   add the B2 destination, save the credentials to the Keychain, and run the
   guided **Set up recovery key** flow, which generates the passphrase, adds it to
   the repo, and immediately runs a **Keychain-bypassed restore drill** to prove
   the paper copy alone can recover the archive. (A CLI path is documented in
   USER_MANUAL for headless hosts.)

### Retention (what the future purge will and won't touch)

A photo is **purge-eligible only when both** are true:

- it is **older than `keepWindowDays`** (default **365**), **and**
- it is **not pinned** — not in a **"Save"** album, not tagged a **"save"**
  keyword, and (optionally) not a **Favorite**.

Everything else is kept. Recent photos and anything you've flagged to Save stay
in Photos on all your devices.

## Install the toolchain

```bash
brew install pipx && pipx install osxphotos   # osxphotos is a Python CLI (no Homebrew formula)
brew install exiftool                          # rsync ships with macOS
```

The host that runs the export must have **originals on disk** (Photos →
Settings → iCloud → *Download Originals to this Mac*). A host on *Optimize Mac
Storage* should set `downloadMissingFromICloud: true` in the profile; that fetch
uses the **PhotoKit** path by default (`usePhotoKitForDownload`, osxphotos
`--use-photokit`), which requests originals from iCloud directly instead of the
AppleScript path that can time out and kill Photos on indeterminate stragglers.

## Usage (`pattic`)

```bash
swift build                       # build the CLI
BIN=$(swift build --show-bin-path)/pattic

$BIN doctor                       # check osxphotos / exiftool / rsync
$BIN init                         # write a starter profile to edit
$BIN plan                         # preview the osxphotos commands (runs nothing)
$BIN export --dry-run             # plan-only osxphotos pass, no writes
$BIN export                       # run the archive: export → mirror → verify → cloud
$BIN export --deep                # verify with SHA-256 (slow, thorough)
```

Profiles live at `~/Library/Application Support/PurpleAttic/profile.json`
(override with `--profile`). Edit `primaryDestination` and
`mirrorDestinations` before your first run — these are now the **drive/volume
roots** (e.g. `/Volumes/PRO-G40`); the archive is nested under the
`archiveSubfolder` (default **"Photos Archive"**) on each, so originals land at
`/Volumes/PRO-G40/Photos Archive/originals`. The **Cryptomator vault is exempt**
— its copy is written at the vault root. Set `archiveSubfolder` to `""` to write
at the drive root instead.

## Sender mode — archive a second Mac (`pattic agent`)

To preserve photos from a **second Mac** (e.g. a different iCloud account, or a small-disk
laptop), run **sender mode** on that Mac. It's one-way and **export-only — it never purges**:
it exports that Mac's Photos to an **external SSD** (so the internal drive stays untouched) and
`rsync`s the archive **over SSH** to this receiver. Reuses the same export engine, so the result
is the same metadata-rich archive as the core flow.

```bash
# On the SOURCE Mac:
./install-sender.sh                 # builds pattic, scaffolds config + SSH key
$EDITOR ~/Library/Application\ Support/PurpleAttic/sender.json   # set stagingRoot + remote.*
pattic agent plan                   # preview
pattic agent run --dry-run          # plan the export, ship nothing
pattic agent run                    # first run = full backup; later = new items only
./install-sender.sh --install-agent 3600   # schedule hourly via launchd
```

Recommended for a perpetually-full small drive: **move the Photos library onto the SSD and set
"Download Originals to this Mac"** — that frees the internal disk *and* means every original is
local (no iCloud-download step). Config lives in `sender.json` (separate from `profile.json`); the
source Mac needs Full Disk Access on the `pattic` binary, and its SSH key authorized on the
receiver.

### Permissions (required before any run)

The app **blocks Dry Run and Archive until three macOS grants are in place**, with
inline *Grant…* / *Settings…* buttons in the Archive pane:

- **Full Disk Access** — so osxphotos can read the `.photoslibrary` bundle. FDA
  is granted **per-binary**: the scheduler runs the bundled `pattic` helper
  headless, so it needs its *own* FDA entry — the app's grant doesn't cover it
  for reading the library. The Schedule pane's *Reveal pattic in Finder* button
  drops you onto the binary to drag into the list. (Separately, macOS Sequoia pops
  a recurring *"…access data from other apps"* prompt on scheduled runs that FDA
  does **not** suppress — see HANDOFF.md "Scheduled-run … KNOWN macOS LIMITATION".
  It's daily to minimize it, and **should be scheduled for a waking-hours time** —
  an unattended overnight run just parks on the prompt until you click *Allow*.)
- **Photos Automation** (Apple Events → Photos) — so download-missing / edited
  exports can drive Photos. *Without it osxphotos thrashes ("AppleScript export
  failed 10 consecutive times, restarting Photos app").*
- **Photos Library** (PhotoKit) — used by the guarded purge.

`pattic doctor` reports Full Disk Access for the CLI / scheduled-run path.

## Output locations

- **Run reports** (user-facing): `~/Downloads/PurpleAttic/report-<timestamp>.txt`
- **Detailed logs**: `~/Library/Logs/PurpleAttic/pattic-<profile>-<timestamp>.log`
- **Config/profiles**: `~/Library/Application Support/PurpleAttic/`

## Safety model

- **The archive becomes the master once you purge.** After a photo is deleted
  from Photos it lives only in the archive — so purge is gated on the photo
  being present and matching in **≥2 on-disk copies**, the keep window gives a
  year-plus buffer, and Photos' 30-day *Recently Deleted* is the final net.
- **Purge requires an affirmative toggle and stays human at the delete step.**
  Deletion lives only in the app (`PhotoKitPurger`), never the CLI. macOS shows an
  un-suppressible confirmation on every delete, so even the automated path can only
  *stage* (add verified photos to a "To Delete" album, non-destructively) — you
  empty that album in Photos yourself.
- **Automated nightly staging is opt-in.** With purge enabled **and** "Automatically
  stage nightly" on, a successful scheduled archive identifies the verified-deletable
  set and stages it for you each night; deletion remains a one-click human action.

## The app

`./build-app.sh` builds, signs (Photos entitlements), installs to
`/Applications/PurpleAttic.app`, and relaunches. The GUI panes are
**Dashboard** (the landing pane — end-to-end monitoring: archive health, purge /
space reclaimed, new items, off-site B2, with charts + drill-down), **Archive**
(run + live log), **Schedule**, **Settings** (profile editor), **Off-site**,
**Backup**, and **Purge** (preview + stage/delete + the auto-stage toggle, shipped
OFF). The `pattic` CLI is bundled inside the app at
`PurpleAttic.app/Contents/MacOS/pattic`.

## Roadmap

- [x] Engine + `pattic` CLI (export → mirror → verify → cloud).
- [x] SwiftUI GUI: sidebar, settings, run dashboard, live log.
- [x] Launch-time backup + Settings → Backup UI (PhantomLives standard).
- [x] `build-app.sh` / `install.sh` / icon bundle.
- [x] Previews-only / Optimize-Storage library guard (warns + gates real runs).
- [x] Cryptomator vault unlock status in the UI.
- [x] Guarded PhotoKit purge (osxphotos metadata + ≥2-copy verify + PhotoKit delete), default OFF.
- [x] launchd scheduler (Schedule pane): automated archive, daily/weekly.
- [x] Permissions preflight: Full Disk Access + Photos Automation + Photos Library, hard-gated before a run.
- [x] "Photos Archive" subfolder on physical drives (vault exempt); free-space sanity warning.
- [x] Automated nightly purge **staging** (opt-in): plan in the CLI → app stage-agent → "To Delete" album. Deletion stays human.
- [x] Structured run history + purge audit (`run-history.jsonl` / `purge-audit.jsonl`).
- [x] Monitoring **Dashboard**: archive health, purge / space, new items, off-site B2 — numbers, charts, drill-down.
