# Changelog

All notable changes to PurpleAttic are documented here. This project follows
release-hygiene conventions from the repo root `CLAUDE.md`.

## [0.21.1] — 2026-06-15

Fixes found in live use of the 0.21.0 recovery-key flow.

### Fixed
- **Recovery drill reported a false FAIL.** The Keychain-bypassed restore drill picked its sample
  file by scanning the **local archive**, but restored it **from the snapshot** — so while a backup
  is still seeding (only a partial snapshot exists), it would pick a file the snapshot doesn't
  contain, restore nothing, and report a byte mismatch even though the recovery key was valid. The
  drill now chooses its sample **from the snapshot itself** (`restic ls latest`), so it's
  self-consistent at any seed stage; it byte-compares to the local copy when present, else verifies
  the restored file is non-empty. (`verifyRecoveryKey` + new `firstSmallFileInSnapshot` /
  `parseFirstSmallFilePath`.)
- **Recovery-key log box wasn't copyable.** The log is now selectable (`.textSelection`) and has a
  **Copy log** button, so errors can be copied out.

### Added
- **"Test recovery key" button** — re-run the restore drill against an existing recovery key without
  adding another one (opens the flow straight at the verify step).

### Tests
- +2 (143 total): `parseFirstSmallFilePath` picks the first in-bounds, non-dir, non-dotfile node and
  returns nil on no-match / garbage.

## [0.21.0] — 2026-06-15

Make the off-site (restic → Backblaze B2) layer configurable **entirely in the app — no Terminal**.
0.20.0 shipped the unattended engine but left first-time setup (storing Keychain secrets, adding +
testing the recovery key) as hand-run `security` / `restic` commands. This adds a dedicated
**Off-site** tab that does all of it point-and-click, so a brand-new Mac can be set up end to end
without the command line. The CLI path still works and is documented as the advanced alternative.

### Added
- **Off-site settings pane** (`OffsiteSettingsView` + `OffsiteModel`) with four cards:
  - **Destination** — add/enable a Backblaze B2 destination; edit name, bucket, and path (the
    `b2:<bucket>:<path>` repo string is composed for you); toggle enabled + check-after-backup.
  - **Credentials** — paste the B2 key ID + application key and **Save to Keychain** (written via
    the `security` CLI so restic reads them back non-interactively). A green/red checklist shows
    which of the runtime passphrase / B2 key ID / B2 key are stored. For a brand-new repo the app
    generates the runtime passphrase itself (kept only in the Keychain).
  - **Repository status** — live snapshot count + latest-snapshot time + key count, with Refresh.
  - **Recovery key** — a guided sheet: **generate** a strong word-based passphrase (or type your
    own) → confirm it's written on paper → **add it to the repo** → **re-type it from paper** and
    run a **Keychain-bypassed restore drill** that byte-matches a restored sample against the local
    archive. Proves the paper copy alone can recover the archive before you rely on it.
- **`KeychainStore`** — reads/writes the off-site secrets via `/usr/bin/security` (chosen over
  `SecItem*` so CLI-created items are read back by restic's `security` child without an auth prompt —
  the unattended-read guarantee). Pure argv builders are unit-tested.
- **`RecoveryPassphrase`** — diceware-style generator using `SecRandomCopyBytes` with rejection
  sampling (no modulo bias), word count auto-scaled to ≥100 bits from the system wordlist.
- **`ResticService` admin ops** — `overview` (snapshots + keys for the status panel),
  `credentialPresence`, `addRecoveryKey` (new-key via a 0600 temp file, never in argv), and
  `verifyRecoveryKey` (the in-app recovery drill); plus `ProcessRunner.capture(environment:)`.

### Changed
- **Settings → Destinations** no longer shows the retired Cryptomator vault field; it points to the
  new **Off-site** tab instead.

### Tests
- +12 (141 total): Keychain argv builders, recovery-passphrase entropy/shape/uniqueness + bounded
  uniform index, restic admin argv, snapshots/keys JSON parsing, and the bounded sample-file finder.

## [0.20.0] — 2026-06-15

Re-architect the **off-site copy**: replace the Cryptomator/macFUSE → iCloud Drive vault with a
purpose-built, client-side-**E2EE**, unattended, resumable, verifiable backup driven by **restic**.
The off-site layer is now a **pluggable list of destinations** — Backblaze B2 ships today; an
rclone-backed remote (Dropbox/Proton/S3/rsync.net) is config-only later, no engine change. The two
proven local copies (osxphotos → ROG_WHITE → rsync → LACIE → verify) are unchanged.

### Why
The vault was the source of nearly every unattended-run failure: macFUSE **wedged twice** under
load, it needed a **human to unlock** Cryptomator, it rode a **multi-week iCloud eviction** dance
(iCloud Drive is a sync product, not a backup target — no API, no resumable upload, no integrity
proof), and a manual+scheduled **run collision** wedged it. restic talks to the B2 API directly:
no FUSE, no manual unlock, no eviction, resumable, with a cryptographic `restic check`.

### Added
- **`ResticService`** — drives restic non-interactively. The repo passphrase is supplied via
  `RESTIC_PASSWORD_COMMAND` (restic shells out to `/usr/bin/security` itself, so the passphrase
  never enters PurpleAttic's process); B2 key id/key are read from the Keychain into the child env
  only. `init` is idempotent, `backup`/`check`/`restoreSample` round out the lifecycle, and an
  **offline/unreachable repo is a clean `.skipped`, never a failure**.
- **`CloudDestination`** value type (`kind`: `.resticB2` / `.resticRclone`, `repo`, `keychainService`,
  `enabled`, `checkAfterBackup`) and **`ArchiveProfile.cloudDestinations: [CloudDestination]`** — the
  pluggable destination list, resilient-decoded so old profiles default to `[]`.
- **Single-writer lock (`RunLock`)** — an advisory `flock` (auto-released on crash, unlike a PID
  file; non-blocking) so the hourly, manual, and drive-connect-triggered runs can never overlap
  (the collision that wedged the vault). A run that can't take the lock is a clean no-op.
- **Replaced-primary re-seed safeguard** — if the primary disk was swapped for a blank one but a
  populated mirror is attached, the primary is re-seeded from the mirror *before* osxphotos, so a
  blank replacement triggers a fast local copy instead of a needless full re-export.
- **PurpleMirror integration** — the scheduled archive (`com.bronty13.PurpleAttic.archive`) now has
  a tailored "Photo Archive" job profile and a `.purpleAttic` log parser surfacing live status:
  "Archive up to date", "Waiting for drives", "Skipped (already running)", the current phase, the
  per-destination off-site tally, and run failures.

### Changed
- The engine's cloud phase loops `cloudDestinations` calling `ResticService.backup` (one
  `StepResult` per destination; a skip is non-fatal, exactly like the old "vault not mounted").
- `cloudVaultPath` is **deprecated** — still decodable for back-compat, but ignored by the engine.
  Retire it from the active profile once a restic destination is seeded and restore-verified.
- `restic` (+ `rclone`, for future rclone destinations) resolved in `Tooling` like osxphotos/rsync.

### Tests
- 129 total (+14: ResticService env/arg building for B2 + rclone, password-command quoting, PATH
  augmentation, backup/check arg shape, Outcome skip-not-failure semantics, missing-creds skip; the
  single-writer lock's mutual exclusion + reacquire-after-release + pid write). PurpleMirror +6 for
  the `.purpleAttic` parser states and the tailored job profile.

### Operational (not in code)
- Live B2 setup is a guided, user-driven step: create a private bucket + application key, store the
  restic passphrase + B2 key in the Keychain, add a **recovery passphrase** via `restic key add`
  (written down for a physical safe), and **prove restore with the recovery key alone** before
  relying on it. The Cryptomator vault is decommissioned only after B2 is seeded + both restore
  drills pass.

## [0.19.1] — 2026-06-14

### Fixed
- **Scheduled runs no longer hang at startup.** A launchd-spawned `pattic export` runs in a
  bare environment, and osxphotos froze loading its framework modules there (0% CPU, never
  progressing) — while the identical command ran fine from a terminal. `SchedulerService` now
  invokes pattic through a **login shell** (`/bin/zsh -lc 'exec pattic export …'`) so it and its
  osxphotos child inherit the full user environment (Homebrew PATH, locale, …). Diagnosis was
  empirical: same command, same drive, same DB — only the execution environment differed.

## [0.19.0] — 2026-06-14

Make the Hidden-album behavior explicit and controllable (it was already implicitly included).

### Added
- **`includeHidden` profile option (default ON).** osxphotos *includes hidden photos by default*
  (verified: total == not-hidden + hidden), so the archive has always captured the Hidden album.
  This option makes that explicit and adds the inverse: turning it OFF passes osxphotos
  `--not-hidden` to EXCLUDE the Hidden album. Toggle in Settings → Profile ("Include the Hidden
  album"). Hidden ≠ deleted: a photo you actually delete leaves the library and future runs don't
  see it. (An earlier attempt used a non-existent `--include-hidden` osxphotos flag, which aborted
  the export with exit 2 — corrected to the real semantics.)

### Tests
- 115 total (+1: hidden flag follows the profile — default adds nothing, opt-out adds `--not-hidden`).

## [0.18.0] — 2026-06-14

Hourly scheduling + drive-resilient runs — set the archive to run every hour and have it
quietly do nothing when the drives aren't attached.

### Added
- **Hourly schedule cadence.** `ArchiveSchedule` gains `.hourly` (alongside daily/weekly) —
  a launchd `StartCalendarInterval` with only `Minute`, so it fires at the top of every hour.
  Selectable in Settings → Schedule.

### Changed
- **Scheduled runs are now drive-resilient.** If the **primary** archive drive isn't a
  mounted volume, `ExportEngine.run` now returns a clean, successful *"skipped — primary
  drive not attached"* result instead of throwing — and, crucially, never `createDirectory`s
  under an unmounted `/Volumes/…` path (which would silently write to the boot disk). The
  mirror and cloud copies already skip-and-catch-up when their drive/vault is absent, so a
  later run with everything attached brings all three copies current. This is what makes an
  hourly schedule safe: a run with the drives detached is a no-op, not an error.

### Tests
- 114 total (4 new: hourly calendar-keys / plist / next-run / humanDescription, and the
  primary-drive skip guard).

## [0.17.0] — 2026-06-12

Sender mode — capture a *second* Mac's Photos to an SSD and ship them to a PurpleAttic receiver.

### Added
- **`pattic agent` (sender mode).** A one-way, export-only agent for a *source* Mac (e.g. a small-
  disk second Mac on a different iCloud account): it exports that Mac's Photos to an **external SSD**
  (keeping the internal drive untouched) and `rsync`s the archive **over SSH** to a remote receiver.
  - **Export-only, never purges.** New `SenderConfig` maps to an *export-only* `ArchiveProfile`
    (empty mirrors, no vault, `purgeEnabled` forced off, `reviewNewItems` off), so the sender reuses
    the exact, tested `ExportEngine` export path with **zero changes to the core archive / mirror /
    verify / cloud / purge code**. Same metadata as the core archive (`--exiftool` + XMP sidecars).
  - **Incremental.** First run = full backup; every run after (hourly via launchd) catches only new
    photos/videos (`osxphotos --update`).
  - **Small-disk friendly.** Staging on the SSD means ~zero internal-drive footprint;
    `downloadMissingFromICloud` handles an Optimize-Storage source (recommended: move the library to
    the SSD + "Download Originals" so no iCloud fetch is needed at all).
  - Subcommands: `pattic agent init | plan | run` (`run --dry-run` to preview); config at
    `~/Library/Application Support/PurpleAttic/sender.json`, separate from `profile.json`.
- **`install-sender.sh`** — source-Mac installer: ensures osxphotos/exiftool, builds + installs the
  `pattic` CLI, scaffolds the config, generates an SSH key, and (optionally, `--install-agent
  [seconds]`) loads an hourly launchd agent. Separate from the core `build-app.sh`/`install.sh`.

### Tests
- 9 new sender tests (110 total, all green): export-only/never-purge invariants, download-flag
  pass-through, staging-root nesting, validation, the rsync-over-SSH argv shape (port, identity,
  `BatchMode`, trailing-slash source, single-quoted remote path), and Codable round-trip + tolerant
  decode. Core suite unchanged — no regressions.

## [0.16.0] — 2026-06-11

Retention pin-matching hardened to be case- and whitespace-insensitive on both sides.

### Changed
- **Keep-album / keep-keyword matching now normalizes both sides** (lowercased + trimmed) via
  `RetentionPolicy.normalizeTag`, so every spelling — `Save`, `save`, `SAVE`, `SaVe` — and any
  stray leading/trailing spaces (e.g. a hand-edited `profile.json`) match. The match was already
  case-insensitive; this also closes the whitespace gap and locks the behavior with a test
  enumerating the exact casings. Pin protection is the highest-stakes guard before a purge, so it
  must never miss on capitalization or spacing.

### Tests
- `testPinMatchingIsCaseAndWhitespaceInsensitive` asserts a space-padded, odd-cased keep-list entry
  pins an asset whose own keyword/album is in a different casing, across `Save/save/SAVE/SaVe/sAvE`.

## [0.15.0] — 2026-06-11

Auto-pause-and-resume on a busy library — the purge rides out iCloud sync instead of failing.

### Added
- **Auto-pause / auto-resume on `PHPhotosErrorDomain 3300`.** Both the stage-to-album and direct-
  delete paths now treat a 3300 as *"the library is busy"*, not *"this batch is bad"*. When a large
  purge backs up Photos' iCloud sync, PhotoKit rejects **every** asset-mutation (delete *and*
  album-add) until the backlog drains — and a relaunch/reboot does **not** clear it (verified:
  even a trivial 8-asset album-add throws 3300 in that state). So instead of burning through every
  batch and failing, PurpleAttic now **pauses on the failing batch with escalating back-off
  (30s → 60s → 120s → 300s, capped) and re-probes, resuming automatically the moment Photos accepts
  the change** — pacing the purge to iCloud's own throughput. It reports `done/total (%)` and the
  next retry time throughout, so the run never looks frozen and you can leave it unattended. After
  ~45 min of a single batch staying blocked it stops cleanly and tells you to re-run once sync
  settles (`PhotoKitPurger.runBatches` / `pauseBackoff` / `maxBusyProbesPerBatch`).
- **Cancel + determinate progress.** A **Cancel** button stops a stage/delete after the current
  batch (and during a back-off wait) via a thread-safe `PurgeCancellation` token, and a determinate
  progress bar replaces the old indeterminate spinner (`AppState.purgeFraction` / `cancelPurge()`).

### Fixed
- **Case-sensitive UUID resolution.** `PHAsset.fetchAssets(withLocalIdentifiers:)` is
  case-sensitive and `PHAsset.localIdentifier` carries the UUID **uppercase**; a lowercase UUID
  resolves to nothing (verified: lowercased UUIDs resolved 0/8, uppercase 8/8). osxphotos already
  emits uppercase, but `resolveAssets` now normalises defensively so a future metadata source can't
  silently match zero assets.

### Notes
- The 3300 wall is a Photos/iCloud library-state condition, **not** a PurpleAttic bug — proven via a
  live PhotoKit diagnostic (read/resolve and empty-album *creation* succeed, but any op touching
  existing assets fails until sync settles). PhotoKit can't be unit-tested headlessly; this change
  was validated against the real library with the diagnostic harness.

## [0.14.0] — 2026-06-11

"Stage to album" — the scalable purge path for tens of thousands of photos.

### Added
- **Stage-to-album deletion.** A new **"Stage N to 'To Delete' album"** button adds the
  verified-deletable photos to a regular album (**`PurpleAttic — To Delete`**) and then the user
  deletes them **inside Photos.app** with a single confirmation. Why this is the right
  architecture at scale:
  - **Adding to an album is non-destructive → shows no confirmation**, so PurpleAttic stages the
    whole set **unattended, batched, with a progress bar** (`PhotoKitPurger.stageToAlbum` +
    `findOrCreateAlbum`; `AppState.stageForDeletion`).
  - **Photos.app's own engine then does the bulk delete**, which **paces itself through iCloud
    sync and shows native progress** — so it avoids *both* walls that break direct deletion at
    scale: the **un-suppressible macOS confirmation that fires per `deleteAssets` call** (~66
    prompts at 1000/batch) and the **`PHPhotosErrorDomain 3300` choke** when iCloud is busy
    digesting a large deletion backlog.
- The **direct-delete** path remains (now labelled as such) for small sets, with copy explaining
  the per-batch confirmation + 3300 trade-offs.

### Why
A real 65k-photo purge exposed that direct third-party `deleteAssets` can't scale: macOS forces a
confirmation per batch (un-suppressible), and after ~24k deletions iCloud chokes (`cloudd` pegged)
so further deletes fail 3300 until the backlog clears — no amount of retry/backoff can outrun that
hands-off, because the confirmation re-prompts. Staging sidesteps both: the app does the silent
correlation + album-population, and Apple's native delete handles the throttling.

## [0.13.0] — 2026-06-11

Delete in resilient batches — fix `PHPhotosErrorDomain 3300` on a large purge.

### Fixed
- **Deleting the verified set failed wholesale** with *"Photos refused the deletion …
  (PHPhotosErrorDomain error 3300)"*. Cause: `PhotoKitPurger` deleted **all 65,627 assets in a
  single atomic `performChanges`** — PhotoKit rejects a delete that large, and (being atomic)
  one un-deletable asset would also fail the entire request, so **nothing** was deleted.
- **`deleteAssets` now deletes in chunks** (`defaultBatchSize` 1000), each its own
  `performChanges`. A chunk that fails is **skipped and counted** (the run continues instead of
  aborting), the user dismissing a macOS confirmation **stops cleanly** and reports what was
  already deleted, and re-running the purge retries anything not yet removed. `Outcome` gained
  `failed` / `batchError` / `cancelled`; the Purge pane shows per-batch progress and a precise
  summary (deleted / skipped-retry-next-run / unmatched). PhotoKit's atomic-delete ceiling sits
  between 1000 and 5000 (1000 proven; 5000 also returns 3300), so 1000 is the chunk size — macOS
  confirms once per chunk.
- **Purge pane text is now selectable** (`.textSelection(.enabled)`) so counts, the file list,
  and error messages can be copied (e.g. to report an issue).
- **Retry-with-back-off on transient 3300.** A chunk that fails is retried with a 5/15/30 s
  back-off before being skipped — error 3300 frequently means Photos is briefly choked while
  syncing a bulk deletion, and a short wait lets it recover, turning a skip into a success. The
  Purge pane shows the wait so the UI doesn't look frozen. (Deep choking still needs Photos/the
  Mac restarted — the documented cure — but transient hiccups now ride through automatically.)

### Note
PhotoKit deletion requires the app's Photos grant + the macOS GUI, so it can't be validated by a
headless harness the way the preview was; the batched design makes the first run **self-reporting**
(it either deletes a chunk and continues, or names the exact error on a small chunk) rather than an
opaque all-or-nothing failure. macOS shows one delete confirmation per chunk.

## [0.12.0] — 2026-06-11

Fix purge verification rejecting ~all photos (the `--exiftool` size delta).

### Fixed
- **The ≥2-copy purge gate verified almost nothing** — a real preview marked only **368 of
  66,279** eligible photos "deletable" and skipped 65,911, making purge useless. Root cause:
  verification matched each photo's archived file against the **Photos `original_filesize`**,
  but the export embeds metadata via **`osxphotos --exiftool`**, so every archived original is
  a few hundred bytes **larger** than its pre-export size — the exact-size check failed for
  67,122 of the present files (only files exiftool happened not to resize matched).
- **New verification model:** a candidate is verified when its filename is present in the
  primary **and** a mirror holds a **byte-identical** copy (the primary/mirror size-sets for
  that name intersect). This proves two *consistent* copies exist — the real intent of the
  gate — without depending on the pre-export size. After the fix, the same library verifies
  **65,627 of 66,279** (the 652 still skipped are the shared/"Shared with You" items excluded
  from the archive in 0.10, which correctly have no archived copy and must never be deleted).
  Validated end-to-end against the live 68,151-record library + both mounted drives.
- Tests: 100 total (regression: exiftool-resized file still verifies; primary/mirror size
  disagreement → unverified; name-absent → unverified).

### Note
The ideal long-term correlation is osxphotos' export DB (uuid → archived path), noted in
HANDOFF; the name + cross-copy-consistency model is the robust, version-independent fix shipped
now. The 30-day Recently Deleted net and the independently-verified complete archive remain
backstops.

## [0.11.0] — 2026-06-11

Fix the purge preview crashing on osxphotos' non-standard JSON.

### Fixed
- **Purge preview failed with "Couldn't parse osxphotos JSON: …isn't in the correct
  format"** on a real library. Root cause: `osxphotos query --json` emits **non-standard
  JSON literals** — `Infinity` / `-Infinity` / `NaN` (in a video's audio-waveform
  `energyValues`, and unset scores). Python tolerates them; Swift's JSON parser rejects
  them outright, so the entire preview (and thus any purge) was impossible. `PhotoMetadataQuery`
  now runs a single-pass, **string-aware** sanitizer over the osxphotos output that rewrites
  those bare literals to `null` **only in value position** — a keyword / album / caption that
  literally contains "Infinity" or "NaN" is left byte-for-byte intact (backslash-escaped quotes
  handled). Validated end-to-end: a 727 MB / 68,151-record real query that previously failed
  now decodes cleanly. None of the rewritten fields are ones the retention logic reads.
- Tests: 98 total (+5 — value-position rewrite, negative-number/normal-value safety, literals
  inside strings preserved, escaped-quote string tracking, full-record decode round-trip).

## [0.10.0] — 2026-06-11

Stop chasing ghosts — exclude "Shared with You" + shared-album items.

### Added
- **`excludeSharedAndSyndicated` (on by default).** The export now passes osxphotos
  **`--not-syndicated --not-shared`**, skipping **"Shared with You"** (Messages /
  syndication) items and **shared-album** items. These aren't your originals and have
  **no downloadable master**, so they otherwise linger forever as bogus "missing"
  originals — exactly the false gap that sent a multi-hour download chase after photos
  that could never come down. New Settings toggle (Source card); `ExportPlan` emits the
  flags only when enabled. Old profiles decode with it **on**. Your own iCloud **Shared
  Library** photos are unaffected (that's `--shared-library`, which you do own).
- Tests: 93 total (+4 — flags present-by-default / disabled, migration defaults).

### Why
The first production download-missing run left "3 missing" that no tool — osxphotos
(AppleScript or PhotoKit) or Photos' own Export Unmodified Original — could fetch.
Diagnosis: all three were **shared/syndicated** content (a texted pasta photo
`syndicated=True`, a shared video `shared=True`), not owned originals. osxphotos counts
them as "missing" because they have no master. Excluding them makes the missing count
reflect only photos you actually own. Incident: 2026-06-11, Vortex.

## [0.9.0] — 2026-06-10

PhotoKit download path — make `--download-missing` reliable (stop killing Photos).

### Added
- **`usePhotoKitForDownload` (on by default).** When download-missing is enabled,
  PurpleAttic now passes osxphotos `--use-photokit`, fetching missing originals from
  iCloud via **PhotoKit** instead of the default AppleScript path. A new Settings
  toggle (shown only when download-missing is on) exposes it; `ExportPlan` emits
  `--use-photokit` only alongside `--download-missing`. Old profiles decode with it
  **on**.
- Tests: 89 total (+5 — PhotoKit flag present-by-default / disabled / absent-without-
  download-missing, and migration defaults).

### Why
The default osxphotos download path drives Photos over **AppleScript**; on a slow or
**indeterminate (`incloud=None`)** iCloud asset that request **times out**, and
osxphotos' retry loop **terminates Photos** (`killall`) and re-tries — which on a real
run wedged both Photos and the export with **0 of 44 stragglers downloaded** (and was
the cause of a separate "Photos not responding" hang). `--use-photokit` requests the
original directly and needs no Photos-Automation grant. Incident: 2026-06-10, Vortex.

## [0.8.0] — 2026-06-10

"NEW PHOTOS TO REVIEW" — stage each incremental run's new items for review.

### Added
- **New-photo review staging (on by default).** On an **incremental** run, the
  items newly added to the archive (originals + JPEG, with sidecars) are also
  copied into a dated batch folder under **"NEW PHOTOS TO REVIEW"** (default
  `~/Downloads/PurpleAttic/NEW PHOTOS TO REVIEW/<timestamp>/`), so just-arrived
  photos can be handed off (to keep) or deleted after review — without touching
  the backup set. New `ReviewStaging` (Core) snapshots each export pass's files
  before the run and copies the set-difference afterwards. **Skipped on the
  first/baseline run** (everything is "new" then, so nothing is duplicated) and
  whenever a pass adds nothing. Re-exported edits of existing photos keep their
  path and are not re-staged.
- Profile gains `reviewNewItems` (default true) + `reviewFolderPath` (nil →
  default); Settings → **New-photo review** card (toggle + folder). The run
  report and log show the staged count + batch path; `pattic plan` shows the
  setting. Old profiles decode with the feature **on**.
- Tests: 84 total (+6 — set-difference, snapshot/copy round-trip, profile defaults).

## [0.7.0] — 2026-06-10

The three post-first-run enhancements: live progress, graceful errors, mount guard.

### Added
- **Live progress dashboard.** The Archive pane now shows a **phase stepper**
  (Export HEIC → Export JPEG → Mirror → Verify → Cloud) with per-phase state
  (pending/running/done/failed/skipped) + elapsed, total elapsed, the current
  file being copied (rsync) / files checked (verify), and a live count of files
  written during each export pass (polled, since osxphotos' own progress is
  TTY-only and silent when piped). Replaces the bare "Running…" spinner for
  these multi-hour runs. New `RunProgress` + `RunProgressTracker` in Core;
  `ExportEngine(onProgress:)` streams snapshots; `AppState.progress` publishes them.
- **Graceful error handling.** The benign exiftool *metadata-embed* failures
  (Bad/Truncated MakerNotes, "Not a valid HEIC/JPEG/PNG", Bad ExifIFD, "Error
  reading image data") no longer flood the log as scary "❌️ Error" lines. New
  `OsxphotosLine.classify` reclassifies them as a counted **"sidecar-only"**
  notice (the image + `.xmp` are archived; only the in-file embed was skipped),
  suppresses the per-file/retry spam, keeps genuine export failures distinct, and
  lists the affected photos in the run report. The run summary carries
  `metadataEmbedSkips`.
- **Mirror/vault mount guard.** New `VolumeReadiness` — before copying, each
  mirror base must exist and (for a `/Volumes/*` path) be a genuinely mounted
  separate volume. An unmounted drive is **skipped with a warning** instead of
  the engine creating the folder on the **boot disk** and rsyncing hundreds of GB
  there. (Found as a risk in 0.6.2.)

### Changed
- Mirror/verify are now reported as aggregate phases across all configured
  mirrors (N ok / skipped / failed), and a failed/skipped mirror is no longer
  verified.
- Tests: 78 total (+16 — line classification, volume readiness, progress tracker).

## [0.6.5] — 2026-06-10

Third cloud-copy fix — the vault rsync also can't create temp files (`--inplace`).

### Fixed
- **Cloud copy to the Cryptomator vault still aborted (`mkstempat`/`utimensat:
  No such file or directory`)** after the 0.6.4 chown fix — this time ~24k files
  in, on a duplicate-named file (`_MG_4667 (1).JPG`). openrsync writes each file
  to a temp name then renames it, and that temp-file creation fails on the
  macFUSE/Cryptomator volume for some names. The vault copy now adds `--inplace`
  (write directly to the final file, no temp/rename). Verified by re-copying the
  exact folder that failed (1,044 files, exit 0). Combined with 0.6.3
  (`.DS_Store` exclude) and 0.6.4 (`--no-owner --no-group --no-perms`), all three
  openrsync↔Cryptomator incompatibilities are handled. The APFS mirror keeps
  atomic temp-then-rename writes (only the FUSE vault needs `--inplace`). 62 tests.

## [0.6.4] — 2026-06-10

Second cloud-copy fix — the vault rsync also can't preserve owner/group/perms.

### Fixed
- **Cloud copy to the Cryptomator vault still aborted (`fchownat: Function not
  implemented`).** With 0.6.3 the copy got past `.DS_Store` and transferred the
  first file, then died because rsync `-a` preserves owner/group/perms and the
  macFUSE/Cryptomator volume doesn't implement `chown`/`chmod`. The cloud copy
  now adds `--no-owner --no-group --no-perms` (content + timestamps still
  transfer; perms are moot inside an encrypted container). The **on-disk mirror
  keeps `-a`** (APFS supports those). Verified against the live vault. Mirror +
  verify remain confirmed (verify: 350,513 files match). 61 tests.

## [0.6.3] — 2026-06-10

Cloud-copy fix found by the first end-to-end run (mirror + verify now confirmed).

### Fixed
- **Cloud copy to a Cryptomator vault aborted on `.DS_Store`.** With the 0.6.2
  rsync flags, mirror (→ APFS) and verify both succeeded (verify: 350,500 files
  match — the openrsync fix is confirmed), but the cloud rsync to the macFUSE
  Cryptomator vault died at the first file: openrsync copies each file to a temp
  name then renames it into place, and that `renameat` fails on the FUSE volume
  ("renameat: No such file or directory") for `.DS_Store`, aborting the whole
  transfer (exit 1, 0 files copied). `ExportEngine.rsyncCopyArgs` now excludes
  `.DS_Store` and `.osxphotos_export.db*` from every copy (mirror + cloud).
  Verified end-to-end against the live vault. These are dotfiles, which
  `VerifyService` and `ArchiveIndex` already skip (`.skipsHiddenFiles`), so
  excluding them creates no verify discrepancies and they were never archive
  content. (59 tests.)

## [0.6.2] — 2026-06-10

Critical mirror/cloud fix found by the first full run.

### Fixed
- **Mirror, verify, and cloud all failed on stock macOS.** The engine hard-coded
  rsync's `--info=progress2`, but macOS's default rsync is **openrsync** (reports
  "2.6.9 compatible"), which rejects that flag and aborts in 0.1s with a usage
  error. Result: the mirror copied nothing, **verify then reported every primary
  file as a discrepancy** (349k false positives — an empty mirror, not real
  corruption), and the cloud copy failed identically. The exports themselves were
  fine. `ExportEngine.rsyncCopyArgs` now picks flags the available rsync supports
  — `--info=progress2` only for a real rsync 3.x (e.g. Homebrew), otherwise plain
  `-ahv` which every rsync understands. Tested across openrsync / rsync 3.x /
  classic 2.6.9 / empty-banner. (58 tests.)

## [0.6.1] — 2026-06-09

Fixes to the 0.6.0 preflight, from first use.

### Fixed
- **Photos Automation could never be granted** ("nothing to grant under
  Automation; the error never clears"). The app sent Apple Events without an
  `NSAppleEventsUsageDescription` in its Info.plist, so macOS never showed the
  consent prompt and never listed PurpleAttic under Automation. Added the usage
  string (the `com.apple.security.automation.apple-events` entitlement was
  already present for hardened runtime) — the "PurpleAttic wants to control
  Photos" prompt now appears and the grant sticks.
- **False low-space warning on the Cryptomator vault.** The vault is a macFUSE
  volume, which doesn't report the `volumeAvailableCapacityForImportantUsage`
  resource key, so free space read as 0/absent despite ample room.
  `FreeSpaceCheck.freeBytes` now uses `statfs()` (what `df` uses), which reports
  correctly on APFS/HFS *and* macFUSE.

## [0.6.0] — 2026-06-09

Run-cleanly hardening: a permissions preflight, a "Photos Archive" subfolder on
physical destinations, and a free-space sanity check.

### Added
- **Permissions preflight (hard gate).** New `PermissionsService` (app) checks
  the three macOS grants a clean run needs — **Full Disk Access** (probed via
  the shared `Permissions.fullDiskAccessLikely` Core helper), **Photos
  Automation** (Apple Events → Photos, via `AEDeterminePermissionToAutomateTarget`),
  and **Photos Library** (PhotoKit). The Archive pane shows a per-grant panel
  with inline *Grant…* / *Settings…* buttons, and **Dry Run + Run Archive stay
  disabled until all three are granted** (`AppState.runArchive` also refuses as
  defense-in-depth). This closes the failure mode where a missing Automation
  grant sent osxphotos into the "AppleScript export failed 10 consecutive times,
  restarting Photos app" loop.
- **Archive subfolder.** New editable `archiveSubfolder` on the profile (default
  **"Photos Archive"**). You pick a drive *root* (e.g. `/Volumes/PRO-G40`) and the
  archive is nested under `<drive>/Photos Archive/…` so the drive root stays
  tidy. Applies to the **primary + mirrors**; the **Cryptomator vault is exempt**
  (archive written at the vault root). Threaded through `ExportPlan`,
  `ExportEngine` (mirror/verify/cloud), and the `ArchiveIndex`/`PurgePlanner`
  purge path. Empty subfolder = opt-out (archive at the base, pre-0.6 behavior).
- **Free-space sanity check (warning).** New `FreeSpaceCheck` estimates the
  archive footprint from the library's originals size and compares it against
  each destination volume's free space; the Archive pane shows a non-blocking
  warning when a volume looks too small or isn't mounted.
- **`pattic doctor`** now also reports Full Disk Access (and notes the
  Automation requirement); **`pattic plan`** shows the composed archive roots.

### Changed
- `ArchiveProfile` now decodes **every** key with `decodeIfPresent` + defaults,
  so a pre-0.6 `profile.json` (no `archiveSubfolder`) loads cleanly instead of
  failing — it defaults to "Photos Archive".
- `primaryDestination` / `mirrorDestinations` now mean the **drive/volume base**;
  the archive lives in `archiveSubfolder` beneath each. Validation checks the
  base (drive) is mounted. Starter profile destinations are now drive roots.
- Tests: 54 total (+15 — archive-root composition, profile-migration decoding,
  free-space estimate/sufficiency/mount-boundary).

## [0.5.1] — 2026-06-09

Docs only.

### Added
- `HANDOFF.md` — architecture snapshot (safety model, Core/CLI/App module split,
  data flow, topology, gotchas). Registered PurpleAttic in the root `CLAUDE.md`.
- `USER_MANUAL.md` — Vortex first-run walkthrough, pane-by-pane reference, the
  purge workflow, output locations, troubleshooting, and the `pattic` CLI.

## [0.5.0] — 2026-06-09

Phase D: the **scheduler** — a launchd agent that runs the archive on a cadence.

### Added
- **`ArchiveSchedule`** — daily/weekly cadence + time (Codable, persisted in
  settings with backward-compatible decoding). `nextRun(after:)` and
  `calendarKeys` are unit-tested.
- **`LaunchAgentPlist`** — pure builder for the launchd plist (StartCalendar
  Interval, `RunAtLoad` false so it only fires on schedule, Background
  ProcessType, log paths). Unit-tested incl. XML escaping.
- **`SchedulerService`** (app target) — writes the agent to
  `~/Library/LaunchAgents/com.bronty13.PurpleAttic.archive.plist` and loads it
  via `launchctl bootstrap gui/<uid>` (with bootout/retry); `runNow` kickstarts;
  `isLoaded`/`lastRunDate` for status. The agent runs the **bundled `pattic
  export`** — which has no purge path, so automated runs can never delete.
- **Schedule pane** — enable + daily/weekly + time pickers, Apply, live status
  (loaded?, next run, last run), Run Now, Reveal Log, and notes (run on the
  originals Mac; grant Full Disk Access to bundled pattic; purge is never
  automated).
- Tests: 39 total (+8 — schedule keys, plist fields, next-run, escaping).
  The launchctl bootstrap/print/kickstart/bootout sequence was smoke-tested live.

### Notes
- The scheduler archives only. Purge remains manual (Purge pane), OFF by default.

## [0.4.0] — 2026-06-09

Phase C: the **guarded purge** — wired but gated behind `purgeEnabled` (default
OFF) and multiple safety checks. Removes aged, un-pinned photos from Photos
*only* after they're verified in the archive.

### Added
- **`PhotoMetadataQuery`** — reads candidate metadata via `osxphotos query
  --to-date <cutoff> --json` (osxphotos is the source because it reads
  **keywords**, which PhotoKit can't). Decodes uuid/date/favorite/albums/
  keywords/original_filename/original_filesize/ismissing/intrash.
- **`ArchiveIndex`** — filename → byte-size index of an archive's `originals/`
  tree. Verification matches on **filename AND exact size**, independent of the
  osxphotos folder template.
- **`PurgePlanner`** — applies `RetentionPolicy` to the candidates and verifies
  each against the primary + mirrors. A photo is **deletable only when present +
  size-matched in the primary AND ≥1 mirror** (the ≥2-copy gate). Skips trashed
  and unparseable-date records. Pure `plan(...)` is unit-tested.
- **`PhotoKitPurger`** (app target only — never Core/CLI) — the sole deletion
  path: maps osxphotos UUIDs → `PHAsset`s and calls `deleteAssets`, which shows
  macOS's own confirmation. Deletions go to Recently Deleted (30 days).
- **Purge pane** — "Preview Eligible Photos" (read-only: eligible / verified /
  unverified counts, freed space, date range, a sample list) and a guarded
  "Delete N Verified Photos…" button. Delete requires: purge enabled, verified
  candidates, an in-app confirmation, and the macOS confirmation.
- Tests: 31 total (+9 — eligibility, ≥2-copy verification, size-mismatch,
  pinning, trashed/undated skips, index matching).

### Safety
- Purge ships **OFF**. The CLI still has no purge path at all. Unverified
  candidates (e.g. originals not on this Mac) are never deleted.

## [0.3.0] — 2026-06-09

Phase B hardening: the **previews-only library guard** and **Cryptomator vault
unlock status**. Still no deletion engine.

### Added
- **`LibraryInspector`** — detects whether a Photos library is in "Optimize Mac
  Storage" mode (originals only in iCloud). Counts master files under
  `<library>/originals/` and reads `SELECT COUNT(*) FROM ZASSET` from the live
  `Photos.sqlite` (opened read-only + immutable). Flags the library when <90% of
  originals are on disk. Pure threshold (`isLikelyOptimized`) is unit-tested;
  reads degrade gracefully to "unreadable" without Full Disk Access.
  - The Archive pane shows a live status line ("⚠︎ Optimize Storage likely — X
    of Y originals on disk…") with a Recheck button, and a **real run on an
    optimized library now requires an explicit "Run Anyway" confirmation** (dry
    runs are unaffected). The engine logs the same INCOMPLETE-ARCHIVE warning.
- **`VaultStatus`** — reports whether the Cryptomator vault is `notConfigured` /
  `notMounted` / `ready` (mounted + writable). Settings shows a live indicator
  next to the vault path so you know whether the 3rd copy will run.
- Tests: 22 total (+8 — library threshold, path resolution, vault states).

## [0.2.0] — 2026-06-08

Phase B: the **SwiftUI GUI** wrapping `PurpleAtticCore`, plus the app bundle.

### Added
- **`PurpleAttic.app`** (SwiftUI macOS app, `PurpleAtticApp` target):
  - Manual `HStack` sidebar (PhantomLives pattern, not `NavigationSplitView`) +
    `WindowStateGuard`. Four panes: Archive, Settings, Backup, Purge.
  - **Archive** dashboard: Dry Run / Run Archive, a **live streaming log** (via a
    new `AtticLogger.sink`), the last-run summary, and banners for config issues
    / missing osxphotos. Runs the engine off the main thread.
  - **Settings**: full `ArchiveProfile` editor — source library, primary +
    mirror destinations, Cryptomator vault path, HEIC/JPEG toggles, folder
    template, and retention (keep window, keep albums, keep keywords, favorites).
    Shared JSON with the `pattic` CLI.
  - **Backup**: launch-time `BackupService` (zips `~/Library/Application
    Support/PurpleAttic/` → `~/Downloads/PurpleAttic backup/`, 14-day retention,
    5-min debounce, never throws) + the full Settings → Backup UI (toggle,
    retention, folder override, Run Now, recent-backups list). PhantomLives
    ship-blocker satisfied.
  - **Purge** pane: the guarded delete is **shipped disabled** — the
    `purgeEnabled` flag sits behind an affirmative confirmation, and the pane
    lays out every safety gate. No deletion engine yet (Phase C).
  - Sidebar toolchain readiness footer (osxphotos / exiftool / rsync).
- **Bundle infra**: `build-app.sh` (build → sign w/ Photos entitlements →
  install → relaunch + freshness proof), `install.sh` (force-kill + verify),
  `PurpleAttic.entitlements` (photos-library + apple-events), deterministic
  `Scripts/generate-icon.swift` (photo-into-archive-box icon). The `pattic` CLI
  is bundled inside the `.app`.

### Notes
- Built + installed + verified fresh (Developer-ID signed) at v0.2.x.
- Purge remains absent from both the CLI and the GUI's execution paths.

## [0.1.0] — 2026-06-08

Initial scaffold: the archival **engine** + the `pattic` CLI (the safe,
non-destructive half of PurpleAttic). The SwiftUI GUI and the guarded purge
stage come in later releases.

### Added
- **`PurpleAtticCore`** engine library:
  - `RetentionPolicy` — the pure, unit-tested keep/purge predicate. A photo is
    purge-eligible only when it is **both** older than `keepWindowDays`
    (default 365) **and** not pinned by a "Save" album, "save" keyword, or
    (optional) Favorite. Conservative by construction: when in doubt, keep.
  - `ArchiveProfile` / `ProfileStore` — Codable job description (library,
    destinations, formats, retention, purge toggle) persisted as JSON, shared
    by the CLI and the future GUI. Profiles are the reuse mechanism: a second
    Mac / iCloud account is just another profile with `purgeEnabled = false`.
  - `ExportPlan` — pure builder for the `osxphotos export …` argument vector
    (one pass for HEIC originals, one `--convert-to-jpeg` pass for the JPEG
    set). Always emits `--update` (incremental), `--sidecar XMP` + `--exiftool`
    (metadata embedded AND in sidecars), `--touch-file`, `--retry 3`.
  - `ExportEngine` — orchestrates export → rsync mirror (no `--delete`) →
    verify → Cryptomator-vault cloud copy, with a detailed log and a
    human-readable run report.
  - `VerifyService` — inventory (path + size) comparison of each mirror against
    the primary, with optional deep SHA-256. This is the evidence the future
    purge stage will require before deleting anything.
  - `AtticLogger` — timestamped, append-only logs under
    `~/Library/Logs/PurpleAttic/`; run reports under `~/Downloads/PurpleAttic/`.
  - `Tooling` — robust locator for `osxphotos` / `exiftool` / `rsync` that
    probes Homebrew + pipx locations (a Finder-launched app has a minimal PATH).
- **`pattic`** CLI: `doctor` (toolchain check), `init` (write a starter
  profile), `plan` (preview the osxphotos commands + retention, run nothing),
  `export` (run the archive; `--dry-run`, `--deep`). **The CLI never purges** —
  deletion is reserved for the guarded GUI.
- Tests: 14 passing (retention boundary/pinning cases, export-argv assertions).

### Notes
- Requires `osxphotos` (`pipx install osxphotos`) and `exiftool`
  (`brew install exiftool`) to run an export; `rsync` ships with macOS.
- Run host must have originals on disk ("Download Originals"); a host on
  "Optimize Mac Storage" should set `downloadMissingFromICloud: true`.
