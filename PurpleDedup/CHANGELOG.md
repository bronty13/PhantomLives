# PurpleDedup — Changelog

Versions follow `1.0.<commit-count>` derived from git in `build-app.sh`. This file
narrates *what* changed and *why*; bundle versions just label the moment.

## 0.18.4 — Cancel scan + force-quit fallback + docs refresh (2026-05-09)

### Cancel scan, properly

The toolbar Scan button now flips to a prominent red **Cancel** while
a scan is running, bound to **⌘.** so it's reachable even when other
toolbar items push it into the overflow menu. Click it (or hit ⌘.)
and the engine unwinds within ~1 second:

- Every drain loop in the engine (exact + perceptual + video + lookup-
  index) now checks `Task.isCancelled` between each task completion
  and calls `group.cancelAll() + throw CancellationError()` to
  short-circuit instead of waiting for the rest of the in-flight work.
- The walker's `Task.checkCancellation()` calls bail out of the
  `for-try-await` loop. The walker's detached task gets cancelled via
  `continuation.onTermination`.
- `runScan` catches `CancellationError` separately and writes "Scan
  cancelled" to the status line. The on-disk SQLite cache is flushed
  per batch, so cancelling mid-scan doesn't lose work.

### Force-quit watchdog

Some non-cancellable phases (a slow SQLite read against a 100k-row
cache, a very large file already in flight) can outlast the user's
patience. After 4 seconds of "Cancelling…", the toolbar button morphs
into **Force Quit**, which calls `exit(0)`. Brutal but immediate, and
the cache survives.

### Docs refresh

- `HANDOFF.md` rewritten to reflect the actual shipped state through
  0.18.x — Photos lookup mode, inline filter editor, PhotoKit auth +
  Locked-Hidden bypass via direct Photos.sqlite read, Tahoe-specific
  layout fixes (GeometryReader, sheet/popover empty-box bug), 90+
  tests, build-script hardening.
- `README.md` features list now matches reality.

## 0.18.3 — "Only hidden" filter via direct Photos.sqlite read + UUID basename matching (2026-05-09)

### Two stacked bugs killed the hidden-only filter

**Bug 1 — wrong basename:** the Photos filter resolver was returning
PHAsset's user-visible original filename (e.g. `IMG_1234.HEIC`), but
the on-disk files in `<library>/originals/` are UUID-named
(`A00DFFD3-C68D-4884-B03C-14F380EF19CA.jpeg`). The walker's basename
whitelist matched zero files for any active filter. Fixed by extracting
the UUID stem from `PHAsset.localIdentifier`
(`<UUID>/L0/001` → `<UUID>`) — that DOES match the on-disk filename
without extension. `FileWalker` now checks both the full basename AND
the stem against the whitelist.

**Bug 2 — Locked Hidden Album privacy gate:** even with full Photos
access granted, PhotoKit on macOS 14+ refuses to surface
`asset.isHidden == true` to third-party apps. The Locked Hidden
feature gates hidden assets behind biometric auth and PhotoKit
silently returns `isHidden = false` for all of them. Confirmed via
the in-app diagnostic: a 62 215-asset library walked completely with
zero `isHidden = true` results.

### Fix: read Photos.sqlite directly

The library's `database/Photos.sqlite` carries the truth in
`ZASSET.ZHIDDEN` and `ZASSET.ZUUID`. Same TCC grant that lets us walk
`originals/` lets us open the SQLite read-only — bypasses the
PhotoKit privacy gate entirely.

`PhotoKitDeletionService.readHiddenUUIDsFromPhotosSQLite(libraryURL:)`
opens the DB via `sqlite3_open_v2(...?mode=ro&immutable=1)` so locking
isn't a problem when Photos.app has the file open. The SQLite path is
PRIMARY for "Only hidden"; PhotoKit smart album + full walk remain as
fallbacks if the schema shifts in a future macOS update.

### In-app diagnostic line

Status strip now shows a purple `Photos filter: filter[…] → N basenames
· …` line whenever a Photos filter resolves. Lets the user see at a
glance whether the filter is matching anything and which fetch path
won (Photos.sqlite / smart-album / phk-walk). Saves a trip to
Console.app.

### Per-thumbnail "Hidden" badge

When a file in the comparison pane has `photosIsHidden == true`, an
orange `eye.slash` capsule renders at the top-leading corner of the
thumbnail. Pairs with the existing top-trailing KEEP/DELETE chip and
bottom-leading "In Photos" capsule — three visual signals that don't
fight for the same corner.

### `PhotoLibraryFilter.onlyHidden`

New mutually-exclusive-with-`includeHidden` flag on the filter struct.
Backward-compat decoder so older saved filters (without the field) load
cleanly. Surfaced in the inline filter editor as a third toggle in the
"Other" section.

## 0.18.2 — Tahoe layout recovery + faster filter resolution + inline filter editor (2026-05-09)

A big round of fixes for issues that surfaced once a real user tried 0.18:

### Sidebar layout — sources strip rendered off-screen

NSSplitViewItem on Tahoe (macOS 26.x) was reporting the sidebar's content
height at ~2× the visible window (1554pt in a 719pt window), which
pushed the sources strip off the top of the visible area. The user saw
just the empty cluster state and assumed sources were broken. Fixed by
wrapping `clusterListColumn` in a `GeometryReader` and pinning its
inner VStack to `geo.size.height` — SwiftUI now refits the column to
the live window on every layout pass.

`emptyClusterState` also lost its `.frame(maxHeight: .infinity)`, since
that's what was leaking the unbounded intrinsic height to the split
view item in the first place.

### Photos filter resolution — orders of magnitude faster

`PhotoKitDeletionService.matchingBasenames` was calling
`PHAssetResource.assetResources(for:)` once per asset to read the
filename. Each call is a Photos-DB round-trip; on a 50K-asset library
that's tens of thousands of round-trips and the filter resolution
stalled for minutes. Replaced with `asset.value(forKey: "filename")`
which reads the filename off the asset row directly — no per-asset DB
hop. Same data, ~100× faster on a real library.

### Filter editor — inline instead of modal sheet

`.sheet(item:)` and `.popover(isPresented:)` BOTH render as empty white
boxes when the host view sits inside a `GeometryReader`-wrapped
NSSplitViewItem column on Tahoe. Confirmed by replacing the body with a
single Text and seeing the same empty box. Fix: render the filter
editor INLINE inside the sources strip. The funnel button now toggles
the editor as a card right under the source row — no modal hosting,
no ScrollView (which collapsed to 0 height in an unbounded parent),
just natural-height content with a bounded scroll on the album list
itself (some libraries have hundreds of date-named auto-albums).

### Hidden-only filter mode

`PhotoLibraryFilter` gained `onlyHidden: Bool`. When set, the scan ONLY
considers assets in the Hidden album — non-hidden assets are skipped
at the database level via `NSPredicate(format: "hidden == YES")`.
Useful for users who want to dedup their Hidden album in isolation.
Custom `init(from:)` on the filter struct so older saved filters
(without `onlyHidden`) decode cleanly.

### Cluster-row "archived in Photos" badge

When a Photos library is configured as **lookup-only** (the magnifier
icon), exact-duplicate clusters whose content hash matches an asset in
the lookup index now show a small purple `photo.on.rectangle.angled`
icon in the cluster list. Tooltip: "At least one file in this cluster
is also archived in your Photos library — safe to delete the folder
copy." The per-thumbnail "In Photos" capsule in the comparison pane
remains for similar/perceptual clusters where the hash check is
per-file.

### Stale-binary trap closed

`build-app.sh` was silently bundling whichever binary was last linked,
even when the current `swift build` failed. That meant edits could
"succeed" (the bundle re-signed, the .app re-launched) while the user
ran on stale code. Hardened the script to abort with `FATAL: …build
failed — aborting before bundling stale code.` whenever either swift
build step exits non-zero.

### Other small things

- `UserDefaults`-persisted NSSplitView frames are purged on every
  launch (`PurpleDedupAppMain.init`) so a stale saved frame from a
  prior weirdly-sized window can't poison the next layout.
- Photos auth banner now shows a **Reset** button that runs
  `tccutil reset Photos com.bronty13.PurpleDedup` when the OS recorded
  a silent deny (covered in 0.18.1 but expanded with clearer copy).

## 0.18.1 — Photos entitlement + TCC reset path (2026-05-09)

The reason "Open Privacy Settings" wasn't showing PurpleDedup in the Photos
pane: the app was hardened-runtime-signed but missing the
`com.apple.security.personal-information.photos-library` entitlement.
Without it, macOS 14+ silently denies PhotoKit calls and never registers
the app in TCC, so the user has no way to grant access from Settings.

### What changed

- New `PurpleDedup.entitlements` file declaring the Photos entitlement
  (and `com.apple.security.automation.apple-events` so
  `NSWorkspace.launchApplication("Photos")` works under the hardened
  runtime). `build-app.sh` passes `--entitlements` to `codesign` when
  the file is present and warns when it isn't.
- The auth-denied banner now exposes a **Reset** button that runs
  `tccutil reset Photos com.bronty13.PurpleDedup` and immediately
  re-issues `requestAuthorization`. This is the recovery path for
  anyone running an earlier 0.18.0 build that left a stale silent-deny
  in their TCC database.
- Banner copy updated to explain the silent-deny scenario explicitly,
  rather than telling the user to navigate Settings (where the app
  doesn't yet appear).

### After updating

If you ran any pre-0.18.1 build, you need to clear the stale TCC entry
once. Either click **Reset** in the banner, or run from Terminal:

```
tccutil reset Photos com.bronty13.PurpleDedup
```

Then click **Grant Photos access** — macOS's prompt will appear, and
PurpleDedup will subsequently show up in System Settings → Privacy &
Security → Photos.

## 0.18.0 — Photos lookup mode + inline auth prompt (2026-05-09)

### Photos library lookup mode

Per-source toggle (magnifying-glass icon next to the funnel on each
`.photoslibrary` source). Switches the library from "scan target" to
"reference index":

- Lookup-mode sources are walked and content-hashed but DON'T appear in
  any cluster. Their files are never marked DELETE.
- For every file in your regular folder sources, the comparison pane
  shows a purple "In Photos" badge when that file's content hash also
  appears in a lookup-mode library.

This answers "is this folder duplicate also already in my Photos library?"
without conflating the two — folder dedup decisions stay clean and the
Photos library serves as a read-only oracle.

Implementation:
- `ScanSource.isLookupOnly` flag.
- `CachedScanEngine` splits sources into lookup vs scan, builds the lookup
  index in a dedicated stage (logged as `[STAGE lookup]`), runs all
  clustering / perceptual / video stages on scan-mode sources only.
- `ScanEngine.Result` carries `photosLookupHashes: Set<String>` +
  `photosLookupCount` through to the GUI.
- `ComparisonView.loadMetadata` queries the cache for each file's content
  hash and renders a purple "In Photos" capsule in the bottom-leading
  corner of any thumbnail that matches the lookup index.

The plain (non-cached) engine doesn't support lookup mode — lookup
sources are filtered out before the scan, so the badge stays empty in
that path. Use the cached engine (default) for lookup support.

### Inline Photos access prompt

The "Photos library files are read-only here" hint is no longer just
text. When auth is `notDetermined`, a **Grant Photos access** button
calls `PHPhotoLibrary.requestAuthorization(for: .readWrite)` directly —
the system prompt appears in front of PurpleDedup. On grant, every
Photos source already in the list is automatically unlocked, no need to
re-add them.

When auth was previously denied or restricted, the button changes to
**Open Privacy Settings**, which jumps straight to the Photos pane in
System Settings via `x-apple.systempreferences:` so the user doesn't
have to navigate the Settings tree manually.

A secondary "Use Photos.app duplicates view" link still surfaces as the
fallback for users who'd rather skip the auth dance entirely.

### Internal

- `PhotoKitDeletionService.requestAuthorization()` returns the new
  authorization status synchronously after the system prompt resolves.
- `Database.file(at:)` reused for per-file content-hash lookup at
  comparison time.
- `ScanSource` re-creation in `runScan` preserves `isLookupOnly`
  through the filter-resolution layer.

## 0.17.0 — Photos library filtering + extended metadata (2026-05-09)

### Per-Photos-library scan filter

Each `.photoslibrary` source now has a filter funnel button next to it.
Click it to open a sheet that constrains what the scan looks at:

- **Albums** — multi-select from your user-curated albums (smart albums
  excluded). Empty = all albums.
- **Media subtypes** — Live Photo / HDR / Panorama / Screenshot /
  High Frame Rate / Time-lapse / Streamed Video. Pick any combination.
- **Favorites only** — restrict to assets with the heart in Photos.app.
- **Include hidden** — by default hidden assets are excluded (matches
  Photos.app's main Library view); flip on to include them.

Filters are applied **at scan time**, not after. Before the walker
descends into `originals/`, `PhotoKitDeletionService.matchingBasenames`
resolves the filter against PhotoKit and produces a basename whitelist;
the walker only emits files in that set, so hashing / clustering /
metadata extraction all benefit from the cut. Filters persist in
`UserDefaults` (encoded as JSON), so they survive relaunches.

The active filter shows up as a one-line summary under the source
("albums: Family · favorites only") so it's never invisible. The funnel
icon tints purple when the filter is active.

### More metadata in the comparison panel

Six new fields surface in the metadata table when populated:

- **Star rating** — 1-5 stars from XMP/IPTC. Photos.app, Lightroom, and
  Capture One all write here.
- **Caption** — IPTC caption-abstract or TIFF ImageDescription.
- **Software** — what wrote the file last ("iOS 17.4.1", "Photoshop 2024",
  "Lightroom 13.x"). Distinguishes camera-original from edited copies.
- **Color profile** — named ICC profile ("Display P3", "sRGB IEC61966-2.1",
  "Adobe RGB"). Helps tell wide-gamut HEIC apart from sRGB JPEG re-exports.
- **Photos edited** — `PHAsset` adjustment flag — was this asset edited
  inside Photos.app?
- **Burst keeper / Burst ID** — when the asset is part of an iPhone burst
  series, surfaces whether it's the user-picked keeper and the shared
  burst identifier so siblings can be spotted.

### Internal

- `ScanSource` gains optional `allowedBasenames` whitelist (set by the
  filter materialiser before the walker runs).
- `PhotoKitDeletionService.allUserAlbumNames()` for the sheet's album
  picker; `matchingBasenames(filter:)` for the scan-time resolution.
- `MetadataExtractor` reads `kCGImagePropertyTIFFSoftware`,
  `kCGImagePropertyTIFFImageDescription`,
  `kCGImagePropertyIPTCCaptionAbstract`,
  `kCGImagePropertyProfileName`, and IPTC/XMP star rating.
- `FileMetadata` adds `software`, `colorProfile`, `caption`, `starRating`,
  `photosHasAdjustments`, `photosBurstIdentifier`,
  `photosIsBurstRepresentative`.

### Deferred for next iteration

- People/face detection (needs a heavy inverted-index pass over all
  smart-album people collections — saving for a later round).
- Subtype filtering on non-Photos sources (currently only honoured for
  `.photoslibrary` sources).
- Reverse-geocoding GPS coordinates to readable place names.
- XMP hierarchical subjects, color labels.
- macOS Finder color tags (`com.apple.metadata:_kMDItemUserTags`).

## 0.16.0 — Photos metadata + cross-source dedup highlighting (2026-05-09)

### Photos library metadata in the comparison panel

When a selected cluster contains files inside a `.photoslibrary` and the user
has granted Photos access, the metadata table now surfaces:

- **Photos albums** — every user-curated album the asset belongs to (smart
  albums like Recents/Hidden are excluded). Shows up as e.g. "Photos albums
  Family · Vacation 2024 · Untagged".
- **Photos subtypes** — Live Photo / HDR / Panorama / Screenshot /
  High Frame Rate / Time-lapse / Streamed Video. Reads `PHAsset.mediaSubtypes`.
- **Photos favorite** — ★ yes / no. The heart in Photos.app.
- **Photos hidden** — yes / no. Whether it lives in the Hidden album.
- **Photos created** — `PHAsset.creationDate`, which can differ from
  EXIF/file mtime when Photos.app's own metadata wins.

Implementation: `PhotoKitDeletionService.fetchMetadata(forPath:)` reuses the
basename → `PHAsset.localIdentifier` index (built lazily when the user
acts on Photos library files). Returns nil when auth is denied so non-
authorised libraries still surface regular EXIF without errors.

### IPTC keywords for ALL files

`MetadataExtractor` now reads `kCGImagePropertyIPTCKeywords` from any photo
that carries them — independently of Photos.app. Lightroom, Capture One,
ExifTool, and Photos export workflows all write keywords here. New
**Keywords** row appears in the metadata table when populated.

### Cross-source dedup detection

When the same content lives in TWO of your scan sources — e.g. a photo
that's BOTH inside `~/Pictures/Photos.photoslibrary` AND on disk at
`~/Downloads/Master/IMG_4521.jpg` — the cluster is "cross-source." The
underlying engine already clustered them; this exposes the relationship
in the UI:

- **Link icon** on cluster rows where members come from 2+ different
  scan sources. Hover for "Files in this cluster span multiple scan
  sources."
- **"Cross-source only" toggle** in the bulk-actions row, visible when
  there are 2+ sources. Filters the cluster list (and the keyboard-nav
  ⌘↑/⌘↓ pool) to only cross-source clusters.
- **Concrete use case**: scan your Photos library + your `~/Originals/`
  folder, hit the toggle, and see only the photos you've kept in BOTH
  places — typically the ones you can drop from the Originals folder
  because Photos.app already has them.

### Tests + build

- 80 tests, all passing.
- New code (PhotoKit metadata + cross-source filter) is integration-shaped;
  PhotoKit needs a real authorised library and the cross-source filter
  needs SwiftUI render-tree state to test meaningfully. Both verified via
  manual smoke testing.

## 0.15.0 — Three spec FRs: rotated, stage-folder, dry-run (2026-05-09)

### FR-2.7: Rotated-copy detection

`RotatedClusterer` finds photos that are exact-content duplicates under
90 / 180 / 270° rotation — the case where a friend e-mailed back your
sunset shot turned sideways and the regular perceptual matcher blew past
it because rotated bytes are visually unrelated to the upright pHash.

- **Algorithm**: per file, compute pHashes at all four rotations.
  `rotationDistance(a, b)` is the minimum Hamming distance across the 16
  cross-rotation pairs. Default threshold = 4 (tighter than the
  similar_photo default of 6 because a true rotation should be near-exact).
- **`PerceptualHasher.hashWithRotations(imageAt:)`**: one HEIC decode +
  one grayscale rasterize + three buffer rotations + four DCTs. Pure
  in-memory rotations (transpose-and-flip + reverse) so the cost on top
  of a regular hash is ~µs, not ms — the decode dominates either way.
- **GUI**: lazy "Find rotated" button alongside "Find bursts" in the
  bulk-actions row. New pink-accented "Rotated duplicates" section in
  the cluster list. Each cluster row shows the relative rotations of its
  members ("90° / 180°"); the comparison header reads e.g. "Rotated
  copies: 3 files · rotations 0° / 90° / 270°".
- **Tests added (6, total 80)**: rotate-90 buffer math (3×3 hand-checked
  + 32×32 four-rotations-equals-identity property), 180°-equals-reverse,
  identical-rotation-array clusters, 90° detected across a pair, no-match
  on completely-different hashes, URL exclusion, end-to-end with a
  programmatically-rotated PNG round-tripped through `hashWithRotations`.

### FR-5.5: Stage folder destination

- **`AppSettings.stageFolderPath`** — when set, files marked DELETE
  move to that folder via `TrashManager.Destination.folder(URL)` instead
  of the Trash. Operation log records source AND destination, so Cmd+Z
  restores from the stage folder the same way it restores from Trash.
- **Settings → Engine → Deletion destination**: section showing the
  current destination ("Trash" by default), a "Choose stage folder…"
  button, and a "Reset to Trash" button. Setting persists across launches
  via UserDefaults.
- **Toolbar adapts**: "Trash N" button becomes "Stage N" with a
  tray-arrow-down icon when a stage folder is configured. Status message
  on completion names the actual destination so the user can find their
  files.

### FR-5.9: Dry-run plan export

- **"Save plan…" toolbar button** appears whenever there are clusters
  to review. Writes a JSON file containing every cluster (with kind +
  ID + member count + reclaimable bytes) and every file in those
  clusters (with effective decision, reason, and isManualOverride flag).
  Nothing on disk changes — pure audit output.
- **Default location**: `~/Downloads/PurpleDedup/` per the PhantomLives
  default-output-directory convention. Filename includes a timestamp so
  multiple exports in one session don't overwrite each other.
- **Use cases**: send the plan to a non-technical family member for
  review before committing the actual delete; week-over-week diff to see
  what changed; sanity-check a 200-cluster scan before clicking Trash.

### Tests + build

- 80 tests, all passing.
- `.app` rebuilt and Developer-ID signed; version 0.15.0.

## 0.14.0 — Phase 6.5: PhotoKit "Marked for Deletion" album round-trip (2026-05-09)

PurpleDedup can now act on Apple Photos library duplicates. Files marked
DELETE that live inside a `.photoslibrary` package are queued in a
*Marked for Deletion in PurpleDedup* album in Photos.app — the user opens
Photos, reviews the album, and finalises the delete inside Apple's own
tooling. Trashing files behind Photos.app's database would leave dangling
DB references and break Live Photo pairings; this round-trip is Apple's
documented safe pattern.

- **`PhotoKitDeletionService`** (Core, `Sources/PurpleDedupCore/PhotoKit/`):
  - `currentStatus()` / `requestAuthorization()` — wraps `PHPhotoLibrary`'s
    auth flow into a small `Authorization` enum (`notDetermined / denied /
    restricted / limited / authorized`) so callers don't import PhotoKit
    types directly.
  - `markForDeletion(paths:)` — finds the right `PHAsset` for each path,
    gets-or-creates the album, and bulk-adds via
    `PHAssetCollectionChangeRequest` in one `performChanges` block.
  - **Lookup**: lazy `[basename: localIdentifier]` index built once per
    library per session by enumerating `PHAsset.fetchAssets(...)` and
    keying on the primary resource's `originalFilename`. ~0.5 s for a
    50K-asset library on M-series; reused across all subsequent deletions.
  - Returns a `MarkResult` with `queued`, `unmatched`, `failed` lists so
    the GUI can surface partial successes.
- **`NSPhotoLibraryUsageDescription`** added to the bundle Info.plist by
  `build-app.sh`. Without this the system never shows the PhotoKit prompt
  and `requestAuthorization` returns `.denied`.
- **`ScanSource.init(url:isLocked:)`** — `isLocked` now optional; nil keeps
  the auto-lock-for-`.photoslibrary` default, but the GUI passes
  `isLocked: false` when PhotoKit auth is granted so files inside the
  library can be marked DELETE.
- **GUI integration**:
  - Adding a `.photoslibrary` source triggers an auth request. Granted →
    source un-locked; denied/limited → stays read-only with the existing
    "use Photos.app's Duplicates feature" hint.
  - The hint banner adapts: it now reads "Files marked DELETE will land in
    the Marked for Deletion in PurpleDedup album" when auth is granted.
  - `runTrash()` splits the batch: regular files → `TrashManager` (Cmd+Z
    undo applies), Photos files → `PhotoKitDeletionService` (Photos.app
    handles undo via "Recently Deleted").
  - Status message after a mixed batch reads e.g.
    "Moved 5 file(s) to Trash · 12 queued in Photos.app's \"Marked for
    Deletion in PurpleDedup\" album. Open Photos.app to finalise.
    Cmd+Z to undo the Trash batch."
- **Limitations** (documented in HANDOFF for 6.6):
  - Same-basename collisions across multiple PHAssets resolve first-write-
    wins. Modern libraries don't tend to have this; visible in the
    `unmatched` list when it does.
  - iCloud Optimised Storage stubs aren't surfaced by the `originals/`
    walker because the bytes aren't on disk. PhotoKit-driven enumeration
    (instead of folder walk) is the 6.6 fix.
- **Tests**: 72 (unchanged — PhotoKit needs a real library + permission
  grant; integration testing requires manual smoke). Algorithm-shaped
  pieces (album get-or-create logic, basename indexing) live behind the
  `Photos` framework's API surface and can't be unit-tested without
  fixtures we don't have.

## 0.13.0 — Phase 7.5: Session resume + opt-in notarization (2026-05-09)

### Resume mid-review across app launches (7.5a)

- **`Decision`, `ClusterDecisions`** now `Codable` (with custom URL-as-path
  serialisation since URL keys round-trip awkwardly through `JSONEncoder`).
- **`SessionState`** snapshot persists to
  `~/Library/Application Support/PurpleDedup/session-state.json` on every
  change to the in-memory decisions or manual-override maps. Reads back
  the same data on first window appearance. Cluster lists themselves
  aren't persisted — they re-derive from the next scan, which the cache
  makes ~0.2s warm.
- **Auto-scan on launch** when restored sources still resolve on disk:
  the cluster list re-populates immediately and the persisted decisions
  visibly re-attach by stable cluster ID. Quit mid-review, relaunch, and
  the same cluster you were looking at is right where you left it.
- **ID-based reattachment**: persisted decisions are keyed by the same
  stable cluster IDs the GUI uses (`exact:<sha>`, `photo:<urls>`,
  `video:<urls>`, `burst:<urls>`). New files create new clusters with no
  persisted decisions; deleted files leave orphaned entries that don't
  match any current cluster and harmlessly sit in the JSON.
- **Body refactored** into layered computed views (`bodyTopLayer` →
  `bodyMiddleLayer` → `bodyBottomLayer`) to keep each level under the
  SwiftUI Tahoe type-check budget. Comparison column and pre-flight sheet
  also extracted.

### Opt-in notarization (7.5b)

- **`build-app.sh` notarization gate**: setting `NOTARIZE_PROFILE=<name>`
  before invoking the script triggers `xcrun notarytool submit` against
  Apple's notary service after signing, then `xcrun stapler staple` to
  embed the ticket. Without the env var, builds skip notarization
  (current personal-use default).
- **Setup documented in `INSTALL.md`**: app-specific password, `xcrun
  notarytool store-credentials`, single command to build a notarized
  bundle. The end result: a .app that launches on any Mac without the
  "developer cannot be verified" Gatekeeper alert, even offline (because
  the ticket is stapled to the bundle).
- **Defensive checks**: notarize-with-ad-hoc-signing combination logs a
  warning and skips (notary would reject anyway). Submission failures
  log the full plist to `/tmp/notarize.plist` for troubleshooting.

### Tests

- 72 tests, all passing. No new tests in this turn — both features are
  integration-shaped (filesystem persistence + a build-script branch)
  and exercised by manual smoke testing rather than unit harness.

## 0.12.0 — Phase 7.3+7.4: Granular trash + custom rule chain + folder priority (2026-05-09)

Two related features: per-cluster / per-file trash actions for users who
don't want to batch every decision into one Trash button, and configurable
selection rules so the keeper-picking logic can match the user's mental model.

### Granular trash (7.3)

- **Trash N duplicates** button in the comparison-pane header — appears only
  when the currently-shown cluster has pending DELETE files. One click trashes
  just those files (with the same preflight modal + Cmd-Z undo as the bulk
  Trash button).
- **Trash this file now…** menu item in the per-thumbnail right-click menu —
  trashes one specific file with a one-line preflight, no need to mark
  DELETE first.
- Both reuse the existing PreflightView, TrashManager, operation log, and
  undo state. Single state knob (`pendingTrashSubset`) routes whichever
  subset the user requested through the same confirm pipeline.

### Custom rule chain + folder priority (7.4)

- **`Rule.folderPriority`** — new selection rule. Configured by an ordered
  list of folder paths; files inside an earlier-listed folder beat files in a
  later-listed folder, and either beats files outside every listed folder.
  Directly addresses the "keep originals over Downloads" decision the path
  display previously surfaced but couldn't act on automatically.
- **`SelectionContext`** — pure-data parameter to `SelectionEngine.decide`
  that carries the folder list. Engine stays a pure function; rule chain
  serialises as `[String]` of rule names without per-case associated values.
- **Settings → Rules tab**: full editor for the smart-select rule chain.
  Every available rule is listed (active above, disabled below); ↑/↓ buttons
  reorder, − removes, + adds. Each rule shows a one-line description so
  users don't have to read source to understand what "Most EXIF metadata"
  means. Folder-priority editor sits below: Add folder…, ↑/↓ reorder, −
  remove. Persisted to UserDefaults (`selectionRuleNames`,
  `folderPriority`).
- **Live config**: `ContentView` rebuilds the chain from settings on every
  `ensureDecisions()` call. Edit the chain in Settings while the app is
  running, look at the next cluster, and the new rules apply — no rescan.
- **Tests added (3, total 72)**: folder priority wins inside listed folder,
  list order respected (earlier beats later), falls through when no file
  matches.

## 0.11.0 — Phase 7.1+7.2: Keyboard review flow + burst-series detection (2026-05-09)

Two productivity adds: faster keyboard-driven review, and a fourth dedup
algorithm that catches what the perceptual matcher misses.

### Keyboard-driven review (7.1)

- **Reviewed checkmark** in cluster list rows: green = engine recommendation,
  orange-filled = manual override applied. Lets you see at a glance how
  many groups still need attention without opening each one.
- **Keyboard nav**:
  - `⌘↑` / `⌘↓` — previous / next cluster (wraps at ends)
  - `⌘⏎` — approve current cluster's recommendation, jump to next
    undecided cluster (the "review wizard" loop: tap ⌘⏎ until done)
  - `⌘N` — skip to next undecided cluster without committing
- **"Approve & next"** button visible in the comparison-pane header for
  trackpad-driven reviews; runs the same handler as `⌘⏎`.

### Burst-series detection (7.2)

`BurstClusterer` finds groups of photos taken within a small time window
(default 3s) that are perceptually related at a wider threshold than the
default similar_photo bar. Targets the "10 burst-mode shots of the same
moment" pattern that's distinct enough to escape the strict pHash gate
(≤6) but clearly redundant once you see the timestamps.

- **Algorithm**: sort by capture date → build sliding-window time runs →
  inside each run, union-find on pairwise pHash distance ≤16 → emit
  clusters of size ≥2. A→A→B→B in one rapid window splits into TWO
  bursts, not one.
- **Lazy by default**: a "Find bursts" button in the cluster-list bulk
  actions row, not a scan-time stage. Reads EXIF capture dates only when
  clicked, so normal scans stay at their current speed. Files already in
  an exact cluster are excluded (they're byte-identical, not visually-
  rapid-fire).
- **GUI**: new orange-accented "Burst series (N)" section in the cluster
  list. Cluster row shows the time window + pHash diameter; comparison
  pane displays it like a similar-photo group.
- **Tests added (7, total 69)**: empty input, two close-time-similar shots
  cluster, time-distant clones don't, distinct subjects in same window
  split, capture-date range tracking, URL exclusion, sort order.
- **Deferred**: scan-time burst integration (would require persisting
  capture dates in the cache). Lazy works fine for tens of thousands of
  photos; eager only matters at 100K+.

## 0.10.0 — Phase 7.0: Session persistence + bulk actions (2026-05-09)

Quality-of-life pass on the daily review flow.

- **Sources + thresholds persist across launches** via `AppSettings`. Five new
  fields on the settings store: `lastSourcePaths`, `photoThreshold`,
  `videoThreshold`, `includeSimilarPhotos`, `includeSimilarVideos`. Restored on
  first appearance of `ContentView`; auto-saved via `.onChange` whenever any
  of them mutate. Sources whose on-disk path no longer resolves are silently
  pruned during restore so a missing folder never blocks app launch.
- **No auto-scan on launch.** Restored sources stay un-scanned; the user clicks
  Scan when ready. The status strip says "Restored N source(s) from last
  session. Click Scan to refresh." — and the cache makes that re-scan fast for
  unchanged files anyway.
- **Bulk actions in the cluster column**, visible whenever there are clusters:
  - **Apply to all** — runs the rule chain on every cluster that doesn't yet
    have a decision. Already-decided clusters short-circuit, so it's safe to
    click multiple times. Speeds up the "approve everything as suggested"
    workflow which is the most common review path.
  - **Clear overrides** — wipes every manual KEEP/DELETE override across all
    clusters back to engine recommendations. One click instead of right-
    clicking each thumbnail. Disabled when there are no overrides.
- **Drag-drop reliability fix**: `.onDrop` moved off the NavigationSplitView
  root (where macOS Tahoe's column-level drop regions intercepted events
  first) and onto the sources strip itself — both the dashed empty-state
  rectangle and the populated section. Adds visual targeting feedback (blue
  border + "Release to add folder" caption when something's being dragged
  over) and a `loadDataRepresentation(forTypeIdentifier: "public.file-url")`
  fallback for the cases where Sequoia/Tahoe fails to deliver folder URLs
  through the modern `loadObject(ofClass: URL.self)` API.

## 0.9.0 — Phase 6: Apple Photos library support (read-only) (2026-05-09)

PurpleDedup now scans Apple Photos libraries directly and surfaces duplicates
inside them — without risking the library's database. Drop a `.photoslibrary`
package into the sources list and it gets recognised, walked, and clustered
alongside any regular folders.

The deletion path stays in Photos.app: PurpleDedup tells you what to delete,
Photos.app's own Library → Duplicates feature does the actual delete. This
sidesteps the entire class of risk where trashing files behind Photos.app's
back leaves dangling DB references.

- **`.photoslibrary` auto-detection** in `ScanSource`. Any URL ending in
  `.photoslibrary` is recognized; the new `ScanSource.isPhotosLibrary` flag
  flows through the rest of the pipeline. The init forces `isLocked = true`
  for these sources, so files inside can never accidentally be marked DELETE
  by the rule chain.
- **`FileWalker` Photos-aware path**: when traversing a `.photoslibrary`
  source, the walker enters `originals/` and skips `database/`,
  `resources/derivatives/`, etc. — the bundle internals Photos.app uses for
  its own bookkeeping never appear in scan results. `skipsPackageDescendants`
  is dropped for this one walk so the per-letter shard subdirs (originals/A/,
  originals/B/, …) get fully traversed.
- **`TrashManager` belt-and-braces**: rejects any file path containing
  `.photoslibrary/` with a clear `insidePhotosLibrary` error. The
  auto-locked source already prevents this from ever being reached, but if a
  future code path adds Photos files un-locked we still refuse to act.
- **GUI badge + hint**: Photos library sources show with a 🟣 photo icon in
  the sources strip. When at least one Photos library is active, an
  always-visible info banner explains: "Photos library files are read-only
  here. PurpleDedup will surface duplicates inside the library, but trashing
  them must happen in Photos.app (Library → Duplicates)."
- **Tests added (3, total 62)**: scan-source auto-locking, walker traversal
  (only originals/ surfaces; database/ / derivatives/ skipped), TrashManager
  refuses synthesized un-locked Photos paths.
- **Deferred to Phase 6.5**: PhotoKit-based authorization flow + add-to-
  album-based deletion (`PHAssetCollectionChangeRequest` against a "Marked
  for Deletion in PurpleDedup" album that the user reviews inside Photos.app
  before final delete). The current direct-walk approach gives us read-only
  visibility without entitlement / permission complexity; Phase 6.5 lights
  up the round-trip workflow when users actually want to act on results.
- **iCloud "Optimised storage" gap**: when iCloud Photos optimised storage
  is on, `originals/` contains placeholder stubs rather than actual file
  bytes, and ImageIO/AVFoundation will fail to decode them. PurpleDedup will
  log per-file errors and continue; the user has to flip "Download originals
  to this Mac" in Photos.app for full coverage. Documented in HANDOFF.md.

## 0.8.0 — Phase 5: smart-select rules + cleanup workflow + undo (2026-05-09)

The "actually delete the duplicates" phase. PurpleDedup now picks a keeper
per cluster, lets you override per-file, and ships every marked file to the
Trash through a pre-flight modal — with a one-click Undo restore.

- **`SelectionEngine`** (`Sources/PurpleDedupCore/Selection/`): pure-function
  rule chain that ranks files in a cluster and emits a `Decision` per file
  (`.keep(reason:)` / `.delete(reason:)`). Rules are first-applicable-wins:
  apply rule 1, narrow the pool to top scorers, fall through to rule 2 to
  break ties, etc. Final tiebreak is alphabetical path so results are
  deterministic. **Locked sources are never marked DELETE** (FR-1.5),
  regardless of where they fall in the ranking.
- **Default rule chain**: `highestResolution → mostMetadata →
  newestCaptureDate → shortestPath`. The tuning rationale:
  - Resolution first because a 4 K original is almost always preferable to a
    sharing-app downsample.
  - Most-metadata second because hand-shared JPEGs lose EXIF; the camera
    original keeps it.
  - Capture date breaks ties when two files are nominally the same.
  - Shortest path catches " (1)" / " (2)" duplicate suffixes.
  All ten requirements-doc rules are implemented (`Rule.allCases`); custom
  chains land in a future Settings UI but the engine is ready for them.
- **Decision badges in `ComparisonView`**: each thumbnail in the comparison
  pane gets a green KEEP or red DELETE pill with a small reason caption
  ("delete · Highest resolution"). Border color tracks the decision so the
  user can scan the grid at a glance. Right-click any thumbnail for **Mark
  KEEP / Mark DELETE / Clear override**; manual overrides get a tiny hand
  icon so the user can tell what they changed vs what the engine decided.
- **Pre-flight modal** (`PreflightView`): bound to a toolbar
  "Move N to Trash" button that's only visible when there are pending
  deletes. Shows total count, total size, photo/video/other breakdown, and
  the first 20 paths. Destructive-styled confirm; ESC cancels; Return
  confirms. The number in the toolbar matches the navigation subtitle's
  "N marked" text, so users always know the scope of what they're about
  to do.
- **Trash + Undo**: confirm fires `TrashManager.move(...)` per file (each
  hits `FileManager.trashItem` and writes an `operation_log` entry before
  the move). Successfully-trashed files drop out of the in-memory cluster
  list immediately (singleton-membership clusters dissolve back to "no
  longer a duplicate"). Toolbar gains an **Undo (N)** button bound to
  Cmd+Z that restores from the recorded Trash URLs to original paths.
- **Public initializers added** to `ExactClusterer.Cluster`,
  `PerceptualClusterer.Cluster`, and `VideoClusterer.Cluster` — needed
  because the GUI now reconstructs filtered clusters after a Trash run.
- **Tests added (7, total 59)**: `SelectionEngineTests` covers single-file
  clusters, highest-resolution wins, fallthrough on tie, locked-file
  immunity, all-locked clusters, alphabetical fallback when no rule has an
  opinion, and rule-order influence on reasoning.
- **Deferred**: custom rule chain UI in Settings; full undo-stack
  integration with `UndoManager` (current undo only restores the last
  batch); per-cluster apply/skip toggles; Apple Photos library "Marked for
  Deletion" album path (Phase 6 — needs PhotoKit auth).

## 0.7.0 — Phase 4.5: three-pane comparison UI + EXIF/codec metadata (2026-05-09)

Brings home the requirements doc's Phase 4 vision: a real comparison UI you can
actually review duplicates with, not just a cluster list.

- **`MetadataExtractor`** (`Sources/PurpleDedupCore/Metadata/`): pulls EXIF and
  codec metadata for one file, on demand. Photos: capture date, camera make/
  model, lens, ISO, aperture, shutter speed, focal length, GPS — all via
  `ImageIO`'s `kCGImagePropertyExif/TIFF/GPS` dictionaries from the file
  header (no full decode). Videos: duration, codec four-CC, bitrate, fps,
  audio presence — all via `AVAsset` track properties. `FileMetadata.rows()`
  returns ordered, populated-only `(label, value)` pairs the UI can render
  uniformly.
- **`ComparisonView`** (`Sources/PurpleDedupApp/Views/`): the right-hand pane
  of the new three-column shell. Renders the selected cluster's files as a
  `LazyVGrid` of large thumbnails (slider 96-360 px) with double-click →
  Quick Look and right-click → Reveal-in-Finder / Quick Look / Open. Below
  the grid, a side-by-side metadata `Grid` lays out one column per file with
  rows for every populated EXIF/codec attribute. **Cells whose values
  disagree across files in the cluster are tinted orange** so the user's eye
  lands on the differences (FR-3.7 — visual diff indicators). Metadata loads
  lazily on selection via `withTaskGroup`; a fast switch cancels the previous
  load via `task(id:)`.
- **`NavigationSplitView` shell**: replaced the single-column layout with the
  macOS-standard three-pane split: sources sidebar (left) → cluster list
  (centre) → comparison pane (right). Native column-resize gestures, native
  sidebar styling, native `navigationTitle`/`navigationSubtitle`. Top toolbar
  holds the Scan button, Photos/Videos toggles, threshold steppers, and the
  scan-progress spinner.
- **Cluster list rebuilt** for the new layout: `List(selection:)` with
  `.tag` per row drives the comparison pane directly. Inline expansion is
  gone — the comparison pane on the right now shows the full file list, so
  the centre column stays scannable. Same stable composite IDs (`exact:<sha>`,
  `photo:<urls>`, `video:<urls>`) as 0.6.0.
- **`StageTiming`**: `ScanEngine.Result.timing` now carries per-stage
  durations. The GUI's status strip renders
  `walk 0.05s · exact 0.03s · photos 1.20s · videos 4.80s · total 6.10s`
  after every scan so any future regression is visible without dropping to
  the CLI.
- **Sources sidebar**: cleaner empty state ("Drop folders here" placeholder
  with icon), per-row reveal/remove buttons, locked-source padlock icon
  (decorative — locked source UX itself ships in Phase 5).
- **Tests added (5, total 52)**: `MetadataExtractorTests` covers PNG
  dimensions extraction, unsupported-extension graceful empty result, and
  rendering rules for `FileMetadata.rows` (only populated fields, aperture
  formatted as `ƒ/N.N`, shutter as fraction string).
- **Deferred to Phase 5**: smart-select rule recommendation badge ("KEEP" /
  "DELETE" with reason), bulk Move-to-Trash workflow, operation-log undo,
  side-by-side scrollable image diff with synced zoom + pan.

## 0.6.0 — Gemini-class scan speed (2026-05-09)

Scaled down a 4,038-file / 57 GB iPhone library scan from **100.75 s → 19.42 s
(5.2× faster)** on the user's M4 Max + 64 GB. Gemini 2 reportedly does the same
folder in ~15 s; we're now within 30 % of that. Warm scans (cache hot) finish
in 0.23 s vs Gemini's likely-similar warm path.

Three findings drove this; all three needed to land together:

1. **Wedged `VTDecoderXPCService` processes from previous SIGKILLs** were
   silently breaking ALL HEIC decode for the whole user session. A `sample` of
   the stuck `pdedup` showed every worker thread parked in
   `VTTileDecompressionSessionDecodeTile` waiting on a hung XPC reply.
   Mitigation: don't `pkill -9` pdedup mid-scan during dev. Recovery: `killall
   VTDecoderXPCService`. Discovery memo'd in `feedback_purplededup_perf.md`.

2. **CLI was using the non-cached `ScanEngine` path.** All my Phase-4 caching
   work — bulk fingerprint load, batched DB writes, parallel exact stage —
   only existed in `CachedScanEngine`, which the GUI was using but the CLI
   wasn't. Switched the CLI default to `CachedScanEngine`; added `--no-cache`
   for the in-memory path.

3. **Per-video frame cap at 12.** The dominant cost was the video stage:
   `[STAGE video] 90.88s (848 videos)`. Each video sampled 1 frame/second
   through its entire duration with no upper bound — a 5-minute video did 300
   HEVC decodes through the hardware decoder, which serializes. Capped at 12
   evenly-spaced frames per video (`VideoFingerprinter.maxFramesPerVideo`).
   Cluster count dropped from 83 → 81 (two borderline matches lost) — the
   sequence-alignment math doesn't need dense sampling because adjacent 1 Hz
   frames are usually visually similar anyway.

### Other optimizations folded in

- **Parallel photo + video stages** via `async let`. Wall time = max(B, C)
  instead of B + C. They contend for the same hardware HEVC decoder so the
  win was modest in isolation (~10 %), but valuable layered with the frame cap.
- **Bulk cache load** at scan start: one `SELECT * FROM files JOIN
  fingerprints` instead of N `WHERE path = ?` queries. On a 4K-file scan
  that's ~2 s of saved SQLite round-trips.
- **Batched DB writes** at end of each stage instead of per file. Each
  `upsertFingerprint` was its own transaction with fsync.
- **Parallel exact-stage hashing** (`runExactStage` was previously a serial
  for-loop). Cap at `activeProcessorCount`; SHA-1 is hardware-accelerated and
  doesn't compete with the HEVC decoder.
- **HEVC concurrency cap of 6** for perceptual photo stage: HEIC's embedded
  thumbnail is HEVC-compressed, hardware decoder serializes high concurrency.
  Empirically 6 saturates the decoder without contention.
- **Per-stage timing emitted to stderr** (`[STAGE exact] 0.03s`,
  `[STAGE perceptual] 15.80s (3126 photos)`, `[STAGE video] 18.96s (848 videos)`)
  — makes future regression-hunting trivial.

### Cluster fidelity

- 66 exact + 81 similar photos + 81 similar videos on the user's reference
  folder, identical exact and photo counts to 0.5.x (only 2 borderline videos
  no longer cluster, which the user can recover with `--video-threshold 8`).

### Tests

- 47/47 passing. The frame-cap change preserves all `VideoClustererTests`
  behaviours (alignment-window, duration-ratio gate, exclusion semantics) —
  fewer frames in the test fingerprints, same algorithm.

## 0.5.1 — Big-library speed + Quick Look fix (2026-05-09)

Targets the "really slow on a large folder vs Gemini in moments" report.

- **Embedded thumbnail decode for pHash.** `PerceptualHasher.hash(imageAt:)` was
  passing `kCGImageSourceCreateThumbnailFromImageAlways: true`, which forced a
  *full* 24-MP decode of every iPhone photo just to downsample to 32×32 for
  hashing. Switched to `…IfAbsent: true`, which returns the embedded EXIF
  thumbnail (~150-500 px, decode in ~1 ms) when present and falls back to a
  full decode only when not. Expected 10-50× speedup on photo-heavy libraries.
  This is the same trick Gemini uses to scan in seconds.
- **Live Photo `.MOV` companions skipped** in the video stage. iPhone Live
  Photos pair a still HEIC with a 1-3s .MOV; running the full video
  fingerprinter on every companion was a major per-file cost on Photos
  libraries. The HEIC half goes through the photo perceptual stage as normal.
  Detected by same-folder + same-stem + sibling HEIC/JPG signature.
- **Minimum video duration enforced (`>= 2.0s`)**. Documented but not
  previously checked. Sub-2-second clips fail with a clear `tooShort` error
  and the scan continues — they don't produce useful fingerprints anyway
  (1-2 frame samples can't cluster meaningfully).
- **Quick Look context-menu actually uses Quick Look.** The previous "Quick
  Look" menu item called `NSWorkspace.shared.open(url)`, which opens the file
  in the default app (Photos.app for HEIC). Now uses
  `QLPreviewPanel.shared()` via a coordinator that holds the data source for
  the panel's lifetime. Added a separate "Open in default app" menu item for
  the previous behaviour.

## 0.5.0 — Hash speed, thumbnails, app icon (2026-05-09)

Performance and UX pass triggered by user feedback ("really slow" on M4 Max, no
thumbnail previews of duplicates).

### Performance

- **Pluggable content hash** (`ContentHasher.HashAlgorithm`): SHA-256, SHA-384,
  SHA-512, SHA-1, MD5 — all from CryptoKit, no new dependencies. **Default
  changed from SHA-256 to SHA-1.** On M-series, SHA-1 is hardware-accelerated
  *and* half the work, measured ~8× faster than SHA-256 in parallel. The 160-bit
  digest is far past the collision-probability threshold for non-adversarial
  dedup. Pass `--hash sha256` (or any other) to override.
- **`pdedup bench <path>`** subcommand: walks a folder, hashes every file with
  every algorithm, prints a sorted MB/s + collision-count table. Use this to
  validate the right hash for your hardware and dataset. Bench on M4 Max:

  ```
  Algorithm   |  Time      |  Throughput     |  Unique digests / files  |  Digest bits
  ------------+------------+-----------------+--------------------------+-------------
   SHA-1      |   0.001 s  |  21.36 GB/s     |  80 / 80                 |  160
   SHA-512    |   0.003 s  |  9.19 GB/s      |  80 / 80                 |  512
   MD5        |   0.003 s  |  8.84 GB/s      |  80 / 80                 |  128
   SHA-384    |   0.004 s  |  7.94 GB/s      |  80 / 80                 |  384
   SHA-256    |   0.011 s  |  2.71 GB/s      |  80 / 80                 |  256
  ```

- **Parallel exact stage** (`CachedScanEngine.runExactStage`): previously a single
  for-loop hashing one file at a time — left 15 cores idle on M4 Max. Now uses
  `withThrowingTaskGroup` bounded to `activeProcessorCount`. Same shape as the
  perceptual stage. Also moved DB persistence out of the per-task closure into a
  single batched transaction at the end of the stage.
- **`Database.upsertScannedBatch` / `upsertFingerprintsBatch`**: one transaction
  per stage instead of per file. Was the second-largest cost on large libraries
  (each `upsertFingerprint` was its own SQLite transaction with fsync).
- **Video stage concurrency** bumped from `4` to `min(8, ncores/2)` for M-series
  spare-core slack.

### UX

- **Thumbnail previews in cluster rows.** New `ThumbnailView` lazy-loads ~96-px
  thumbnails via ImageIO (photos: embedded EXIF thumbnail when present, full
  decode fallback) and `AVAssetImageGenerator` at t=0.5s (videos). Process-wide
  LRU cache of 256 entries keeps re-renders cheap. Right-click any file row for
  Reveal in Finder / Quick Look.
- **App icon.** New `Scripts/generate-icon.swift` programmatically draws a
  squircle purple gradient with three offset photo cards and a small dedup
  badge. Generated fresh every build, rolled into `AppIcon.icns` by
  `build-app.sh`, referenced from `Info.plist` as `AppIcon`. No bitmap
  fixtures checked in.

### Tests

- `ContentHasherTests.testEmptyFileDigestPinnedPerAlgorithm` pins the
  empty-input digest for **all five** supported algorithms — catches drift if
  any implementation changes silently.
- 47 tests, all passing.

## 0.4.1 — CLI binary rename hotfix (2026-05-09)

Fixes a launch-time regression introduced earlier on this same date: the GUI .app
bundle was containing the *CLI* binary instead of the SwiftUI app, so double-clicking
PurpleDedup.app printed `Error: At least one path is required` and exited.

- **Root cause:** macOS's default APFS volume is case-insensitive. The SwiftPM
  executable products `PurpleDedup` (GUI) and `purplededup` (CLI) collided at the
  same bin-path filename — whichever linked last won. `build-app.sh` then copied
  that single file as both the GUI binary and the CLI binary inside the bundle.
- **Fix:** renamed the CLI product to `pdedup` (Package.swift, main.swift). The
  CLI is now invoked as `pdedup scan ...`. Build script now builds CLI first and
  GUI second as a defensive measure, and runs an `otool -L` check at the end that
  bails loudly if the GUI binary unexpectedly links ArgumentParser (i.e. the same
  regression recurring).
- **User-facing impact:** anyone who set up a `~/bin/purplededup` symlink should
  point it at `pdedup` instead. README, USER_MANUAL, and INSTALL updated.

## 0.4.0 — Phase 4 cache + threshold-without-rescan + launch backup (2026-05-09)

Phase 4 ships the foundational pieces of the requirements doc's "comparison UI"
phase. The three-pane comparison view itself is intentionally deferred — the
high-leverage wins are caching (so adjusting threshold is fast) and PhantomLives
convention compliance (launch-time backup), which everything downstream depends on.

- **`CachedScanEngine`** (`Engine/CachedScanEngine.swift`): wraps the per-stage
  components and consults SQLite before deciding to re-hash. Cache key is `(path,
  sizeBytes, mtimeUnix)`. Tracks per-stage hit/miss counters via `CacheStats` so
  the GUI can show "skipped 1,247 files via cache."
- **Threshold-without-rescan**: changing the photo or video threshold and re-
  running scan reads cached fingerprints out of SQLite, skips the I/O entirely,
  and runs only the clusterers. No new API needed — `CachedScanEngine.scan` is
  the single entry point.
- **`Database.upsertFingerprint`**: atomic file + fingerprint upsert. New
  `file(at:)` and `fileWithFingerprint(at:)` reads. The v2 `fingerprints` table
  gets populated by the scan hot path; the schema didn't need changing.
- **`VideoFingerprint` decode**: round-trips through the SQLite blob via
  `VideoFingerprint.encoded()` / `CachedScanEngine.decodeVideoFingerprint`.
  Schema-version mismatches (future column additions) surface as a benign nil
  decode that triggers a re-fingerprint — never silently produces wrong data.
- **`SettingsStore`** (`SettingsStore.swift`): UserDefaults-backed `AppSettings`
  with `autoBackupEnabled`, `backupPath`, `backupRetentionDays`, `lastBackupAt`,
  `useCachedEngine`. Mirrors `Timeliner`'s shape so the BackupService glue
  drops in identically. (Renamed from `Settings` to avoid shadowing SwiftUI's
  `Settings` scene.)
- **`BackupRunner.runOnLaunchIfDue`** (`Backup/BackupRunner.swift`): the App-
  side glue between `BackupService` (Core, no settings dependency) and
  `SettingsStore`. PhantomLives convention compliance: launch-time auto-backup
  with 5-min debounce, 14-day default retention, prefix-scoped trim. Failures
  log via NSLog and never block app launch.
- **Settings pane**: `SettingsView` with Backup tab (toggle, location picker,
  retention stepper, "Run backup now" button, last-backup readout) and Engine
  tab (cached-engine toggle + threshold-without-rescan explainer). Lives in a
  separate SwiftUI `Settings { … }` scene so `Cmd+,` opens it.
- **Main window**: now consumes `SettingsStore` and switches between
  `CachedScanEngine` and `ScanEngine` per the user's setting (default cached).
  Shows a per-stage cache hit/miss line during scans so the speedup is visible.
- **Tests added (3, total 47)**: `CachedScanEngineTests` — first run misses /
  second run hits, mtime change invalidates only the touched file, threshold-
  without-rescan returns a 100% perceptual cache hit at a different threshold.
- **Deferred to Phase 4.5 / 5**: three-pane comparison UI, EXIF/codec metadata
  extraction (`metadata` table is still empty), QuickLook integration. The
  cache foundation ships first because everything downstream wants it warm.

## 0.3.0 — Phase 3 video fingerprinting (2026-05-09)

Adds the third pipeline stage from `Dedupr-Requirements.md` § 7: visually-similar video
matching via AVFoundation. Re-encoded videos that pass byte-equality with different
bytes are now grouped as `similar_video` clusters alongside `exact` and `similar_photo`.

- **`VideoFingerprinter`** (`Hashing/VideoFingerprinter.swift`): opens a video via
  AVURLAsset, samples 1 frame/second via AVAssetImageGenerator (with
  `appliesPreferredTrackTransform: true` so EXIF-rotated phone videos hash the same as
  upright copies), then runs the existing pHash on each frame. Returns
  `VideoFingerprint = (frameHashes, durationSeconds, width, height, sampleRate)`.
  Frames render at max 256-pixel side; the DCT input is the same regardless of source
  resolution, so 4K and 1080p re-encodes of the same content land at the same hash.
  Format coverage: every codec/container AVFoundation natively decodes (MP4, MOV,
  M4V, MPG, ProRes, HEVC, H.264). MKV / AVI / WMV / WebM are explicitly **not**
  supported in Phase 3 — files in those formats fail per-file (`unsupportedFormat`),
  the scan continues, and the deferred FFmpeg fallback option is documented in
  HANDOFF.md.
- **`VideoClusterer`** (`Clustering/VideoClusterer.swift`): pairwise compare videos at
  ±5-frame alignments, take the smallest mean per-frame Hamming distance, gate by
  duration ratio (0.5–2.0). Threshold default = 6 (same scale as photos). Above-
  threshold pairs unioned into transitive clusters via the existing UnionFind. The
  required-50%-overlap rule prevents a 1-frame "alignment" from false-matching.
- **`PerceptualHasher` refactor**: extracted `hash(cgImage:originalWidth:originalHeight:errorContext:)`
  so the video fingerprinter can reuse the DCT pipeline on AVAssetImageGenerator
  frames without writing them to disk. The URL-based `hash(imageAt:)` still works
  exactly as before.
- **ScanEngine**: third stage runs after the photo perceptual stage. Concurrency
  bounded to 4 in-flight fingerprinters (AVFoundation is internally parallel; more
  contend rather than help). Per-video errors are logged and skipped — one MKV
  doesn't sink the scan.
- **Report**: `similar_video` cluster kind with `maxPairwiseMeanDistance`,
  `durationSeconds`, `frameCount` per file. Top-level `videoSimilarityThreshold`
  echoed back. Cluster-kind switch in consumers stays exhaustive.
- **CLI**: `--video-threshold N` (default 6), `--no-similar-videos` to skip the pass.
- **GUI**: third "Similar Videos" section with duration + frame count + dimensions
  per file, mean-distance diameter per cluster. Independent toggle + threshold
  stepper next to the photo controls.
- **VideoFingerprint encoding**: 8-byte-aligned little-endian blob (count, width,
  height, durationSeconds, sampleRate, then N×8 bytes of frame hashes). Stored in the
  `fingerprints.videoFingerprint` column added in v2 — the schema didn't need
  changing for Phase 3.
- **Tests added (9, total 44)**: `VideoFingerprinterTests` (real AVAssetWriter-built
  fixture round-trips through fingerprint, encoded blob is right size, non-video
  rejected); `VideoClustererTests` (identical = 0, all-ones-vs-all-zeros = 64,
  alignment recovers a 2-frame intro shift, duration ratio gates 1:5 mismatches,
  byte-identical sequences cluster, URL exclusion drops cluster). Test fixtures
  generated programmatically via `TestVideo.build(...)` (AVAssetWriter + H.264) — no
  binary blobs in the repo.
- **Deferred**: full sequence DP alignment for clipped intros >5 frames; per-frame
  BK-tree for >100-video libraries; FFmpeg fallback for MKV/AVI/WMV/WebM. All in
  HANDOFF.md.

## 0.2.0 — Phase 2 perceptual photo matching (2026-05-09)

Adds the second pipeline stage from `Dedupr-Requirements.md` § 7: visually-similar photo
matching. Resized, recompressed, and re-encoded copies that pass byte-equality checks
with different bytes are now grouped as `similar_photo` clusters alongside the existing
exact-byte clusters.

- **`PerceptualHasher`**: pHash + dHash for any image ImageIO can decode (HEIC, JPEG,
  PNG, RAW, …). Implementation is the textbook one (Zauner '10): grayscale 32×32, 2D DCT
  via Accelerate's vDSP, top-left 8×8 low-frequency coefficients, median-thresholded
  bits. dHash uses a 9×8 grayscale + horizontal gradient bits as an independent
  signature. Original image dimensions captured from CGImageSource properties (the
  thumbnail's dimensions are decode artifacts).
- **`BKTree<Payload>`**: Burkhard-Keller tree on Hamming distance. Sub-linear neighbor
  search at low thresholds. Triangle-inequality pruning verified by a 200-hash random
  test against linear scan.
- **`PerceptualClusterer`**: BK-tree query + union-find produces transitive clusters.
  Files already in an exact-content cluster are excluded so the "similar" listing
  doesn't double-report known exact dupes.
- **ScanEngine integration**: perceptual is a second stage after exact; runs only on
  photo-extension files. Hashing is parallelised via `TaskGroup` bounded by
  `activeProcessorCount`. Per-file errors are logged and the file is skipped — a corrupt
  JPEG never sinks the scan.
- **v2 schema migration**: `fingerprints` table (file_id, phash, dhash, width, height,
  videoFingerprint). Append-only on top of v1; `videoFingerprint` is reserved for Phase 3.
- **CLI**: `--similar-threshold N` (default 6, "very similar"; 12 = "loosely similar"),
  `--no-similar` to disable the pass entirely.
- **GUI**: separate sections for exact and similar clusters, similarity diameter shown
  per cluster, threshold stepper alongside the Scan button. Threshold-without-rescan
  (FR-2.5's slider) lands in Phase 4 once the cache is on the hot path.
- **Tests added (17, total 35)**: pHash identity / resize-tolerance / structural-
  difference rejection / dimensions / decode-failure; BK-tree exact / threshold /
  empty / brute-force agreement; UnionFind transitivity; PerceptualClusterer end-to-end
  on synthetic gradients (resized → 1 cluster, exact dupes excluded from similar pass,
  disabled options skip stage); v1→v2 migration; UInt64 hash data round-trip.
- **Deferred**: BLAKE3 (still SHA256), Stage 2 partial-hash filter, GRDB cache on the
  scan hot path, launch-time backup auto-run, threshold-without-rescan UX. All noted in
  HANDOFF.md.

## 0.1.0 — Phase 1 foundation (2026-05-09)

Initial scaffold. Implements the must-have pieces from `Dedupr-Requirements.md`'s
Phase 1 ("Foundation"):

- **Swift package with three targets.** `PurpleDedupCore` is the engine library;
  `PurpleDedupApp` is a SwiftUI macOS app; `PurpleDedupCLI` is the `purplededup`
  command-line binary. CLI and GUI consume the same core verbatim.
- **File enumeration** (`FileWalker`). Streams via `FileManager.enumerator`, filters by
  extension (photo + video sets from the requirements doc), honors `includeHidden`
  and min/max size filters, and propagates per-source `isLocked`.
- **Two-stage hashing pipeline** (`ExactClusterer`). Stage 1 size-bucket prefilter
  drops files whose size is unique. Stage 3 SHA256 (CryptoKit) hashes the survivors.
  Stage 2 (partial-hash quick filter) is intentionally deferred — see HANDOFF.md.
- **Hash function: SHA256 not BLAKE3 yet.** CryptoKit is hardware-accelerated on
  Apple Silicon (~2 GB/s) and ships first-party. The requirements call for BLAKE3
  for higher throughput; that's a Phase-7 swap once we have profiling data justifying
  the dependency.
- **GRDB-backed cache** (`Database`). Phase-1 schema: `files` (path/size/mtime/hash)
  and `operation_log`. Migrations are append-only. Richer tables (fingerprints,
  metadata, sessions, clusters) land with the phases that populate them.
- **Move-to-trash service** (`TrashManager`). Wired but not yet exposed in the UI;
  always uses `FileManager.trashItem`, never `unlink`. Writes the operation_log row
  *before* the filesystem move so audit survives a crash.
- **Backup service** (`BackupService`). PhantomLives convention requires a launch-time
  backup for any app that owns persistent user data; the service exists and is
  unit-tested. Launch-time auto-run is wired up in Phase 4 alongside the Settings
  pane — until then call `BackupService.runBackup(...)` manually if needed.
- **CLI**: `purplededup scan <path>...` emits a JSON report; `purplededup version`
  prints paths. Quiet/verbose flags. Output to file or stdout.
- **GUI**: minimal SwiftUI shell. Drag-drop folders, Scan button, list of clusters
  with reclaimable size. Three-pane comparison view comes in Phase 4.
- **Tests**: `FileWalker`, `ContentHasher` (incl. zero-byte digest pin and >chunk-size
  streaming), `ExactClusterer` (2-copy detection, all-unique zero-hash check, JSON
  round-trip, size-bucket short-circuit), `Database` (migration + upsert + log
  insert), `BackupService` (archive, retention trim by prefix, list-newest-first).
- **PhantomLives compliance**: `build-app.sh`/`run-tests.sh` mirror PurpleIRC's;
  default output `~/Downloads/PurpleDedup/`; backups `~/Downloads/PurpleDedup backup/`;
  SQLite + settings under `~/Library/Application Support/PurpleDedup/`.
