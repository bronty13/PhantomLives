# PurpleAttic

Export your macOS **Photos** library to a plain-file archive you control, keep
multiple **verified** copies (2 on disk + 1 encrypted in the cloud), and — once
you're ready, behind a deliberate guard — **purge** aged, un-pinned photos from
Photos so your live library stays small and browsable.

The whole design is built to avoid the trap of legacy iPhoto/`.photoslibrary`
bundles that become unopenable years later: the archive is **ordinary files in
dated folders, with metadata embedded and in XMP sidecars**, openable by any
image viewer forever.

> **Status: 0.5.0 — full pipeline + scheduler: engine + `pattic` CLI +
> `PurpleAttic.app` GUI, with the previews-only guard, Cryptomator vault status,
> the guarded purge, and a launchd scheduler.** Purge ships **disabled**
> (`purgeEnabled` off) and deletes only photos verified in ≥2 archive copies,
> behind two confirmations. The scheduler archives only — never purges. The CLI
> never deletes.

**Docs:** step-by-step usage is in **[USER_MANUAL.md](USER_MANUAL.md)** (Vortex
first-run, the purge workflow, troubleshooting); the architecture/dev snapshot is
in **[HANDOFF.md](HANDOFF.md)**.

## How it works

```
Photos library ──osxphotos──▶ Primary archive ──rsync──▶ Mirror (2nd disk)
   (originals)                 HEIC + JPEG          │
                                                    └──rsync──▶ Cryptomator vault
                                                                (encrypted, iCloud Drive)
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
4. **Cloud** — the primary is rsynced into a mounted Cryptomator vault (the
   provider only ever sees ciphertext). Skipped + logged if the vault isn't
   unlocked — archival never blocks on it.

### Retention (what the future purge will and won't touch)

A photo is **purge-eligible only when both** are true:

- it is **older than `keepWindowDays`** (default **365**), **and**
- it is **not pinned** — not in a **"Save"** album, not tagged a **"save"**
  keyword, and (optionally) not a **Favorite**.

Everything else is kept. Recent photos and anything you've flagged to Save stay
in Photos on all your devices.

## Install the toolchain

```bash
pipx install osxphotos     # or: brew install osxphotos
brew install exiftool      # rsync ships with macOS
```

The host that runs the export must have **originals on disk** (Photos →
Settings → iCloud → *Download Originals to this Mac*). A host on *Optimize Mac
Storage* should set `downloadMissingFromICloud: true` in the profile.

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
`mirrorDestinations` before your first run.

## Output locations

- **Run reports** (user-facing): `~/Downloads/PurpleAttic/report-<timestamp>.txt`
- **Detailed logs**: `~/Library/Logs/PurpleAttic/pattic-<profile>-<timestamp>.log`
- **Config/profiles**: `~/Library/Application Support/PurpleAttic/`

## Safety model

- **The archive becomes the master once you purge.** After a photo is deleted
  from Photos it lives only in the archive — so purge is gated on the photo
  being present and matching in **≥2 on-disk copies**, the keep window gives a
  year-plus buffer, and Photos' 30-day *Recently Deleted* is the final net.
- **Purge is shipped disabled.** It will require an affirmative Settings toggle,
  a per-run dry-run preview, and macOS's own delete confirmation — and it is not
  in the CLI at all.

## The app

`./build-app.sh` builds, signs (Photos entitlements), installs to
`/Applications/PurpleAttic.app`, and relaunches. The GUI has four panes —
**Archive** (run + live log), **Settings** (profile editor), **Backup**, and
**Purge** (shipped disabled). The `pattic` CLI is bundled inside the app at
`PurpleAttic.app/Contents/MacOS/pattic`.

## Roadmap

- [x] Engine + `pattic` CLI (export → mirror → verify → cloud).
- [x] SwiftUI GUI: sidebar, settings, run dashboard, live log.
- [x] Launch-time backup + Settings → Backup UI (PhantomLives standard).
- [x] `build-app.sh` / `install.sh` / icon bundle.
- [x] Previews-only / Optimize-Storage library guard (warns + gates real runs).
- [x] Cryptomator vault unlock status in the UI.
- [x] Guarded PhotoKit purge (osxphotos metadata + ≥2-copy verify + PhotoKit delete), default OFF.
- [x] launchd scheduler (Schedule pane): automated archive, daily/weekly. Purge stays manual.
