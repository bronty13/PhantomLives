# PurpleDedup — Architecture Handoff

The canonical mental model for the codebase, kept current as the project ships.
The big spec is `~/Downloads/Dedupr-Requirements.md`; this file is the
*implementation* snapshot at version `0.22.2`.

## Mental model

```
   ┌────────────────────────────────────────────────────────────────────┐
   │                         PurpleDedupCore                             │
   │                                                                     │
   │  Walk  →  ExactClusterer ─────────────────────────────────┐        │
   │            (SHA-1, parallel)                              │        │
   │                                                           ├──→     │
   │  Photos →  PerceptualHasher → PerceptualClusterer ────────┤        │
   │            (pHash + dHash)    (BKTree + UnionFind)        │        │
   │  Videos →  VideoFingerprinter → VideoClusterer ───────────┘        │
   │            (≤12 frames)        (aligned mean dist + UF)            │
   │                                          → ScanEngine.Result       │
   │                                          → ScanReport              │
   │                                                                     │
   │  PhotoKit ─── auth, "Marked for Deletion in PurpleDedup"            │
   │               album, per-asset metadata, filter resolution          │
   │  Photos.sqlite ─ direct read (read-only) for hidden-only filter     │
   │               (bypasses macOS 14+ Locked Hidden Album gate)         │
   │  Database (GRDB) ─── files / fingerprints (v2) / operation_log;     │
   │                      bulk-load on scan hot path                     │
   │  TrashManager   ───  Finder Trash / stage folder / PhotoKit album   │
   │  BackupService  ───  zip ~/Library/AS/PurpleDedup; launch auto-run  │
   │  SelectionEngine ─── rule chain → KEEP/DELETE recommendation        │
   │  MetadataExtractor ─ EXIF + IPTC + TIFF + Photos KVC                │
   └────────────────────────────────────────────────────────────────────┘
                ▲                                       ▲
                │                                       │
        ┌───────┴─────┐                         ┌───────┴────┐
        │PurpleDedupCLI│ argparser + JSON       │PurpleDedupApp│ SwiftUI
        │   (pdedup)   │                        │ (PurpleDedup)│ Tahoe-tuned
        └─────────────┘                         └─────────────┘
```

`CachedScanEngine` (an `actor`) is the default orchestrator. Callers pass
`[ScanSource]` + `ScanOptions` + `PerceptualOptions` + `VideoOptions`, get back a
`(Result, CacheStats)` tuple carrying exact / similar-photo / similar-video
cluster lists, the Codable report, and a `photosLookupHashes` set for the
"In Photos" cross-reference badge. The plain `ScanEngine` survives as a
non-cached opt-out.

## Module map

| Path | Role |
|---|---|
| `Sources/PurpleDedupCore/PurpleDedupCore.swift` | Version constants, default URLs |
| `Sources/PurpleDedupCore/Logging/Log.swift` | Per-category `os.Logger`s |
| `Sources/PurpleDedupCore/Indexing/ScanSource.swift` | `ScanSource` (`isLocked`, `isLookupOnly`, `allowedBasenames`); `FileKind`; `ScanOptions` |
| `Sources/PurpleDedupCore/Indexing/FileWalker.swift` | Async streaming enumeration. Photos library shard fast-path when whitelist is set. UUID-stem matching alongside basename matching. |
| `Sources/PurpleDedupCore/Hashing/ContentHasher.swift` | Pluggable content hashing — defaults to SHA-1; SHA-256/384/512 + MD5 also available |
| `Sources/PurpleDedupCore/Hashing/PerceptualHasher.swift` | pHash (32×32 → 8×8 DCT) + dHash + 4-rotation hash family |
| `Sources/PurpleDedupCore/Hashing/VideoFingerprinter.swift` | AVFoundation 1-fps frame extraction, capped at 12 frames per video. Optional `ffmpegFallback: FFmpegProbe.Probe?` retries via `FFmpegFingerprinter` on AVFoundation decode failure (MKV/AVI/WMV/WebM). |
| `Sources/PurpleDedupCore/Hashing/FFmpegProbe.swift` | Locates a system `ffmpeg`+`ffprobe` pair (env var → Homebrew/MacPorts → PATH). |
| `Sources/PurpleDedupCore/Hashing/FFmpegFingerprinter.swift` | FFmpeg-driven fingerprinter for unsupported formats; `ffprobe` for metadata, `ffmpeg -ss …` per frame, then the same `PerceptualHasher` photo path. |
| `Sources/PurpleDedupCore/Clustering/ExactClusterer.swift` | Stage 1 (size) + 3 (content hash) pipeline |
| `Sources/PurpleDedupCore/Clustering/BKTree.swift` | Hamming-distance metric tree |
| `Sources/PurpleDedupCore/Clustering/UnionFind.swift` | Disjoint-set for transitive merging |
| `Sources/PurpleDedupCore/Clustering/PerceptualClusterer.swift` | BK-tree + UF → similar photo clusters |
| `Sources/PurpleDedupCore/Clustering/VideoClusterer.swift` | Sequence alignment + UF → similar video clusters |
| `Sources/PurpleDedupCore/Clustering/BurstClusterer.swift` | EXIF capture-date burst detection |
| `Sources/PurpleDedupCore/Clustering/RotatedClusterer.swift` | 4-rotation pHash family clusterer (FR-2.7) |
| `Sources/PurpleDedupCore/Engine/ScanEngine.swift` | Top-level orchestration (no cache). `Result` carries `photosLookupHashes`. |
| `Sources/PurpleDedupCore/Engine/CachedScanEngine.swift` | Cache-aware orchestrator (default). `[STAGE …]` timing prints, parallel exact/perceptual/video stages, full Cancel propagation via `Task.isCancelled` checks in every drain loop. |
| `Sources/PurpleDedupCore/Reporting/ScanReport.swift` | Codable JSON shape (FR-5.9 dry-run export) |
| `Sources/PurpleDedupCore/Storage/Models.swift` | GRDB record types + UInt64↔Data |
| `Sources/PurpleDedupCore/Storage/Database.swift` | Schema (v1 + v2) + migrator + upsert + bulk `loadAllCachedRows` + `file(at:)` |
| `Sources/PurpleDedupCore/Operations/TrashManager.swift` | `Destination.trash` / `.folder(URL)` + op log; refuses `.photoslibrary` paths |
| `Sources/PurpleDedupCore/Backup/BackupService.swift` | zip-based backup + retention trim |
| `Sources/PurpleDedupCore/Metadata/MetadataExtractor.swift` | ImageIO EXIF + IPTC keywords + TIFF software + ICC color profile + star rating + caption + Photos-app fields |
| `Sources/PurpleDedupCore/PhotoKit/PhotoKitDeletionService.swift` | `actor`. Auth, basename↔localIdentifier index, "Marked for Deletion" album, `fetchMetadata`, `matchingBasenamesDetailed` (with `Photos.sqlite` direct-read fallback for hidden + people), `readPeopleFromPhotosSQLite`, `readUUIDsForPeopleFromPhotosSQLite`, `requestAuthorization`. |
| `Sources/PurpleDedupCore/PhotoKit/PhotoLibraryFilter.swift` | `albumNames`, `personNames`, `includedSubtypes`, `requireFavorite`, `includeHidden`, `onlyHidden`. Backward-compat custom decoder. |
| `Sources/PurpleDedupCore/Selection/SelectionEngine.swift` | `Decision`, `Rule` enum, `RuleChain`, `SelectionContext` — engine recommendation per cluster |
| `Sources/PurpleDedupApp/PurpleDedupApp.swift` | `@main` SwiftUI scene + Settings scene + UserDefaults split-view-frame purge in `init` |
| `Sources/PurpleDedupApp/SettingsStore.swift` | `AppSettings` (data type renamed from `Settings` to dodge SwiftUI `Settings` scene clash). Persists `photoLibraryFilters` as JSON. |
| `Sources/PurpleDedupApp/SessionState.swift` | Per-cluster decisions + manual overrides JSON — survives launches |
| `Sources/PurpleDedupApp/Backup/BackupRunner.swift` | Launch-time auto-backup glue |
| `Sources/PurpleDedupApp/UpdaterController.swift` | `@MainActor` wrapper around `SPUStandardUpdaterController`. Drives the **Check for Updates…** menu and the Settings → Updates tab. Configuration in Info.plist (`SUFeedURL`, `SUPublicEDKey`); see `RELEASING.md` for one-time key setup. |
| `Sources/PurpleDedupApp/Views/ContentView.swift` | NavigationSplitView shell. Layered body (`bodyTopLayer` → `bodyMiddleLayer` → `bodyBottomLayer`) to fit Tahoe type-check budget. `GeometryReader`-wrapped cluster column. Inline filter editor takes over the column when active. Cancel button + Force Quit watchdog. |
| `Sources/PurpleDedupApp/Views/ComparisonView.swift` | Right-pane: thumbnail grid + diff-highlighted metadata table. Per-thumbnail KEEP/DELETE chip, "In Photos" capsule, orange "Hidden" badge. |
| `Sources/PurpleDedupApp/Views/PhotoLibraryFilterSheet.swift` | The filter editor. Renders inline (NOT as `.sheet` — see Tahoe gotchas below). Albums + People + Subtypes + toggles. |
| `Sources/PurpleDedupApp/GeoCache.swift` | Reverse-geocodes EXIF lat/lon → "City, State". In-memory cache + in-flight coalesce; rounded to 3 decimals (~110 m) so a 12-photo burst is one CLGeocoder call. |
| `Sources/PurpleDedupApp/Views/SettingsView.swift` | Backup / Engine / Rules tabs |
| `Sources/PurpleDedupApp/Views/PreflightView.swift` | Trash confirmation modal |
| `Sources/PurpleDedupApp/Views/ThumbnailView.swift` | ImageIO thumbnail loader; uses `kCGImageSourceCreateThumbnailFromImageIfAbsent` so HEIC embedded thumbs hit the fast path |
| `Sources/PurpleDedupApp/QuickLook/QuickLook.swift` | QLPreviewPanel coordinator |
| `Sources/PurpleDedupCLI/main.swift` | ArgumentParser entry point. CLI is `pdedup` (renamed from `purplededup` to avoid APFS case-collision with the GUI binary). |

## Concurrency

- `FileWalker.walk` returns an `AsyncThrowingStream`; the actual enumeration runs
  on a detached `userInitiated` task. Cancellation propagates through the
  consumer's `for-try-await` via `Task.checkCancellation()`; the walker's own
  detached task is cancelled via `continuation.onTermination`.
- `CachedScanEngine` is an `actor`. Its scan splits sources by mode (`.scan`
  vs `.lookup`), builds the lookup index first if any lookup sources exist,
  then runs walking + exact + (perceptual ‖ video) stages.
- Perceptual stage parallelism is **capped at 6** because the macOS hardware
  HEVC decoder serializes — going wider just causes contention on real HEIC
  libraries. Exact + video stages use `activeProcessorCount` (16 on M4 Max).
- Every drain loop in the engine includes
  `if Task.isCancelled { group.cancelAll(); throw CancellationError() }`,
  so user-initiated cancel takes effect within ~1 task-completion interval
  (sub-second for content hashing, sub-second for perceptual at the cap).
- `PhotoKitDeletionService` is an `actor`. PhotoKit's own callbacks aren't
  re-entrant-safe; serializing through the actor avoids the failure mode where
  two simultaneous album-mutation requests deadlock.
- `Database` wraps GRDB's `DatabaseWriter`; GRDB serializes writes internally,
  so we don't add a wrapper actor around it.

## Tahoe-specific gotchas (macOS 26)

These bit us during 0.17–0.18 development. Read this section before changing
the sidebar layout, the filter UI, or the build script.

- **NSSplitViewItem reports 2× content height in NavigationSplitView's
  sidebar.** Without intervention, SwiftUI's saved frame for the sidebar
  comes back at ~1500pt in a ~720pt window, pushing the top of the column
  off-screen. Fix: `clusterListColumn` is wrapped in `GeometryReader { geo
  in … .frame(width: geo.size.width, height: geo.size.height) }`. Force-fits
  every layout pass.
- **Saved `NSSplitView Subview Frames` poison the next launch.** Even with the
  GeometryReader fix, stale UserDefaults entries can reload the broken
  geometry on launch. `PurpleDedupAppMain.init` purges any UserDefaults key
  matching `NSSplitView Subview Frames` or `NSWindow Frame SwiftUI` so the
  next layout starts clean.
- **`.sheet(item:)` and `.popover(isPresented:)` render as empty white boxes**
  inside a GeometryReader-wrapped NSSplitViewItem column on Tahoe. We
  confirmed by replacing the body with a single `Text` and seeing the same
  empty box. Workaround: render modal-style content **inline** within the
  sidebar column. The filter editor takes over the entire column when active
  (sources strip + cluster list hidden, sticky footer at bottom). Sheets
  attached to other surfaces (the preflight Trash confirmation) still work.
- **`com.apple.security.personal-information.photos-library` entitlement is
  required.** Without it, hardened-runtime apps get `.denied` returned from
  every PhotoKit call WITHOUT the OS ever prompting the user OR registering
  the app in System Settings → Privacy & Security → Photos. The bundle
  must be signed with `--entitlements PurpleDedup.entitlements` (which
  `build-app.sh` does automatically). The auth banner in the GUI offers a
  **Reset** button that runs `tccutil reset Photos com.bronty13.PurpleDedup`
  to clear stale TCC denials from older builds that lacked the entitlement.
- **Locked Hidden Album hides assets from PhotoKit.** macOS 14+ refuses to
  surface `asset.isHidden == true` to third-party apps even with full
  library access. The workaround is to read `<library>/database/Photos.sqlite`
  directly (`SELECT ZUUID FROM ZASSET WHERE ZHIDDEN = 1`); same TCC grant
  that lets us walk `originals/` lets us open the SQLite read-only via
  `sqlite3_open_v2(?mode=ro&immutable=1)`. PhotoKit's `smartAlbumAllHidden`
  + full-walk fallback are kept in case the schema shifts.
- **Photos library files are UUID-named, not original-filename-named.** A
  PHAsset's `localIdentifier` looks like `<UUID>/L0/001`; the leading UUID
  matches the on-disk basename stem in `originals/<X>/<UUID>.<ext>`. The
  asset's `filename` property is the user-visible original ("IMG_1234.HEIC")
  which doesn't match anything on disk. Filter resolution returns UUID stems;
  `FileWalker` matches against both full basename AND extension-less stem.
- **`build-app.sh` must abort hard on swift-build failure.** Earlier versions
  of the script silently proceeded past compile errors and re-bundled the
  previous successful binary, which made every Edit invisible to the user
  for hours. Both swift-build invocations now `if !swift build … then exit
  1; fi` with a `FATAL:` prefix.

## What's deferred / known gaps

- **BLAKE3 vs SHA-1.** Default content hash is SHA-1 for speed; SHA-256/384/512
  + MD5 are pluggable via `ContentHasher.HashAlgorithm`. BLAKE3 was specced
  but skipped — first-party CryptoKit does not ship it, and the SIMD
  throughput win doesn't move the needle when the hot path is 99% cache
  hits on warm scans.
- **Stage 2 partial-hash filter.** Skipped. With photo/video sizes the win is
  small and the extra path is one more thing to keep correct. Reconsider in
  Phase 7 if a real library shows the size-bucket short-circuit isn't enough.
- **Stage-3 video matching limits.** Alignment window is ±5 frames — we miss
  matches where the same video has had its first 30 seconds clipped, etc.
  Full sequence-DP alignment (Smith-Waterman over per-frame Hamming) is the
  Phase-7 fix. Pairwise is also O(n²) on candidate count; for libraries with
  thousands of videos we'd want a per-frame BK-tree to prune.
- **Video format coverage.** AVFoundation natively decodes MP4 / MOV /
  M4V / MPG / ProRes / HEVC / H.264. As of 0.21.0 there's an opt-in
  FFmpeg sidecar fallback for MKV / AVI / WMV / WebM — Settings → Engine
  toggle, or `pdedup --ffmpeg`. Probes for a user-installed FFmpeg
  (Homebrew / MacPorts / PATH); we deliberately don't bundle the binary
  to avoid GPL contamination.
- **Debug-build hashing is slow.** SHA / DCT in unoptimised Swift takes ~50×
  longer than release. Always test against `swift build -c release` or
  `./build-app.sh` for realistic timing. (Memorialized in
  `feedback_swift_release_for_perf` memory.)
- **iCloud Photos "Optimised Storage" gap.** When optimised storage is on,
  `.photoslibrary/originals/` files are placeholder stubs without actual
  bytes — ImageIO/AVFoundation fail per file. We log + continue; user must
  flip "Download originals to this Mac" in Photos.app for full coverage.
- **People / face detection — UNNAMED faces.** The People filter (added in
  0.19.0) reads `ZPERSON.ZFULLNAME` / `ZDISPLAYNAME` from `Photos.sqlite`,
  so unnamed face groups ("Person 1, Person 2") aren't surfaced. Letting
  the user pick "any face that resembles X" without naming would need
  `ZASSETFACEFEATURE` embedding lookups, which is a larger project.

## Tests

98 tests in `Tests/PurpleDedupCoreTests/`, all hitting real fixtures (no
FileManager mocking). Highlights:

- `CachedScanEngineTests` — cache hit/miss invariants, lookup-only mode
  splits sources correctly, threshold-without-rescan cache discipline.
- `PhotoLibraryFilterTests` — Codable round-trip including the
  backward-compat path for old saved filters that lack `onlyHidden` /
  `personNames`.
- `FileWalkerTests` — `allowedBasenames` whitelist semantics including
  the basename-OR-stem matching used by the Photos library UUID scheme.
- `BackupServiceTests` — debounce, retention trim, prefix isolation,
  list-newest-first.
- `BKTreeTests` — random correctness check of BK-tree against linear
  scan.
- `PerceptualClustererTests` — exact-cluster files don't double-report
  as similar; threshold sensitivity; OR-of-distances merge via dHash
  alone; pure-noise pairs stay separate under both hashes.
- `CachedScanEngineTests.testClusterMembersInLookupCoversAllMatchingFiles`
  — cluster members + non-cluster files with cached hashes both surface
  in the lookup-crossref set.
- `VideoClustererTests` — ±5-frame alignment window pinned;
  duration-ratio gate enforced.

Image fixtures are *generated* — `PerceptualHasherTests` and
`PerceptualClustererTests` build CGImages in-memory (gradients, checkerboards)
and write them to PNG via CGImageDestination. No checked-in binary blobs.
Video tests use `TestVideo.build(...)` — a real AVAssetWriter pipeline.

## Build + ship

```bash
./build-app.sh         # release build, codesign with entitlements, verify
./build-app.sh && open PurpleDedup.app
NOTARIZE_PROFILE=NOTARIZE_PROFILE ./build-app.sh   # also notarize + staple
```

Keychain profile setup for notarization is one-time:
```bash
xcrun notarytool store-credentials NOTARIZE_PROFILE \
  --apple-id <appleid> --team-id SRKV8T38CD --password <app-specific-pwd>
```

## Where to start (next phase)

The current shipped feature set covers the original requirements doc end-to-
end plus a long list of user-driven additions. Practical next steps in order
of value:

1. **Notarization automation in CI** — direct-download apps still need a
   notarization ticket to avoid the Gatekeeper warning. The `NOTARIZE_PROFILE`
   path is in `build-app.sh` but no automated runner.
2. **Smith-Waterman frame-sequence alignment for video.** Today's ±5-frame
   window misses videos with substantially different leaders (clipped intros,
   different first 30 s). Full DP alignment + per-frame BK-tree pruning would
   make the video stage robust to those cases.

The existing exclusion logic in `runPerceptualStage` / `runVideoStage` (skip
files already in earlier clusters) is the template for any new stage that
should layer on top. Cached fingerprints are the source of truth for
re-rendering UI without a rescan — leverage `Database.fileWithFingerprint(at:)`
instead of walking files.

## Reference impl pointers

When uncertain about a PhantomLives convention, look at:
- **`Timeliner/`** — backup service reference (launch-time auto-run, debounce,
  retention, restore with safety backup).
- **`PurpleIRC/`** — XcodeGen-free SwiftPM bundle build script template,
  encrypted JSON persistence pattern.
- **`MasterClipper/`** — Sparkle integration, GitHub-Releases-as-appcast,
  manual notarization workflow.
