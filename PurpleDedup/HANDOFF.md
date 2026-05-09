# PurpleDedup — Architecture Handoff

The canonical mental model for the codebase, kept current as phases ship. The big
spec is `~/Downloads/Dedupr-Requirements.md`; this file is the *implementation*
snapshot.

## Mental model

```
   ┌────────────────────────────────────────────────────────────────────┐
   │                         PurpleDedupCore                             │
   │                                                                     │
   │  Walk  →  ExactClusterer ─────────────────────────────────┐        │
   │            (SHA256)                                       │        │
   │                                                           ├──→     │
   │  Photos →  PerceptualHasher → PerceptualClusterer ────────┤        │
   │            (pHash + dHash)    (BKTree + UnionFind)        │        │
   │  Videos →  VideoFingerprinter → VideoClusterer ───────────┘        │
   │            (1fps + pHash)      (aligned mean dist + UF)            │
   │                                          → ScanEngine.Result       │
   │                                          → ScanReport              │
   │                                                                     │
   │  Database (GRDB) ─── files / fingerprints (v2) / operation_log;     │
   │                      schema ready, not yet on scan hot path (P4).   │
   │  TrashManager   ───  move-to-trash + op log; not in the GUI         │
   │                      yet (Phase 5).                                 │
   │  BackupService  ───  zip ~/Library/AS/PurpleDedup; launch-time      │
   │                      auto-run wires up in Phase 4.                  │
   └────────────────────────────────────────────────────────────────────┘
                ▲                                       ▲
                │                                       │
        ┌───────┴─────┐                         ┌───────┴────┐
        │PurpleDedupCLI│ argparser + JSON       │PurpleDedupApp│ SwiftUI shell
        │   (pdedup)   │                        │ (PurpleDedup)│
        └─────────────┘                         └─────────────┘
```

`ScanEngine` (an `actor`) is the only orchestrator. Callers pass `[ScanSource]` +
`ScanOptions` + `PerceptualOptions` + `VideoOptions`, get back a `Result` carrying
exact / similar-photo / similar-video cluster lists plus a Codable report.

## Module map

| Path | Role |
|---|---|
| `Sources/PurpleDedupCore/PurpleDedupCore.swift` | App-wide constants & default URLs |
| `Sources/PurpleDedupCore/Logging/Log.swift` | Per-category `os.Logger`s |
| `Sources/PurpleDedupCore/Indexing/ScanSource.swift` | Source + filter types |
| `Sources/PurpleDedupCore/Indexing/FileWalker.swift` | Async streaming enumeration |
| `Sources/PurpleDedupCore/Hashing/ContentHasher.swift` | SHA256 streaming hasher |
| `Sources/PurpleDedupCore/Hashing/PerceptualHasher.swift` | pHash + dHash via vDSP DCT |
| `Sources/PurpleDedupCore/Hashing/VideoFingerprinter.swift` | AVFoundation 1-fps frame extraction → pHash sequence |
| `Sources/PurpleDedupCore/Clustering/ExactClusterer.swift` | Stage 1 (size) + 3 (SHA) pipeline |
| `Sources/PurpleDedupCore/Clustering/BKTree.swift` | Hamming-distance metric tree |
| `Sources/PurpleDedupCore/Clustering/UnionFind.swift` | Disjoint-set for transitive merging |
| `Sources/PurpleDedupCore/Clustering/PerceptualClusterer.swift` | BK-tree + UF → similar photo clusters |
| `Sources/PurpleDedupCore/Clustering/VideoClusterer.swift` | Sequence alignment + UF → similar video clusters |
| `Sources/PurpleDedupCore/Engine/ScanEngine.swift` | Top-level orchestration (no cache) |
| `Sources/PurpleDedupCore/Engine/CachedScanEngine.swift` | Cache-aware orchestrator (Phase 4 default) |
| `Sources/PurpleDedupCore/Reporting/ScanReport.swift` | Codable JSON shape (exact + similar) |
| `Sources/PurpleDedupCore/Storage/Models.swift` | GRDB record types + UInt64↔Data |
| `Sources/PurpleDedupCore/Storage/Database.swift` | Schema (v1 + v2) + migrator + upsert |
| `Sources/PurpleDedupCore/Operations/TrashManager.swift` | Trash / move + op log |
| `Sources/PurpleDedupCore/Backup/BackupService.swift` | zip-based backup service |
| `Sources/PurpleDedupCore/Metadata/MetadataExtractor.swift` | EXIF (ImageIO) + codec (AVAsset) → `FileMetadata` |
| `Sources/PurpleDedupApp/PurpleDedupApp.swift` | `@main` SwiftUI scene + Settings scene |
| `Sources/PurpleDedupApp/SettingsStore.swift` | UserDefaults-backed `AppSettings` (note: data struct is `AppSettings` to avoid SwiftUI's `Settings` scene clash) |
| `Sources/PurpleDedupApp/Backup/BackupRunner.swift` | Launch-time auto-backup glue |
| `Sources/PurpleDedupApp/Views/ContentView.swift` | NavigationSplitView shell (sources / clusters / comparison) |
| `Sources/PurpleDedupApp/Views/ComparisonView.swift` | Right-pane: thumbnail grid + diff-highlighted EXIF/codec table |
| `Sources/PurpleDedupApp/Views/SettingsView.swift` | Backup + Engine settings tabs |
| `Sources/PurpleDedupCLI/main.swift` | ArgumentParser entry point |

## Concurrency

- `FileWalker.walk` returns an `AsyncThrowingStream`; the actual enumeration runs on a
  detached `userInitiated` task so callers' actors don't get pinned by I/O.
- `ScanEngine` is an `actor`. Hashing the stage-1 survivors happens on a detached task
  so the engine actor itself is responsive (cancel etc.) while the scan grinds.
- `Database` wraps GRDB's `DatabaseWriter`; GRDB serializes writes internally, so we
  don't add a wrapper actor around it.

## What's deferred / known gaps

- **BLAKE3 vs SHA256.** Requirements call for BLAKE3 for SIMD throughput. We still use
  CryptoKit SHA256: first-party, hardware-accelerated, zero new dependencies. Swap is
  a one-line change in `ContentHasher.hash(fileAt:)` once we have a profile saying it
  matters. The empty-file digest pin in `ContentHasherTests` will scream if anyone
  switches without updating the test.
- **Stage 2 partial-hash filter.** Skipped. With photo/video sizes the win is small
  and the extra path is one more thing to keep correct. Reconsider in Phase 7.
- ~~**GRDB cache on the scan hot path.**~~ Resolved in Phase 4. `CachedScanEngine`
  reads `(path, size, mtime)` keys from `files`+`fingerprints` and skips re-hashing
  cached entries. FR-6.3's "≥10× speedup on unchanged libraries" target validated by
  `CachedScanEngineTests.testFirstRunMissesCacheSecondRunHits`. FR-2.5's "threshold
  without rescan" — adjust the stepper, click Scan, and the perceptual stage hits 100%
  cache. The plain `ScanEngine` still exists as the simpler reference and as an
  opt-out via `AppSettings.useCachedEngine`.
- **Three-pane comparison UI** (Phase 4.5 — deferred from Phase 4). The current
  `ContentView` is a single VStack with disclosure groups; the requirements doc's
  three-pane (sources / cluster list / comparison) layout with side-by-side image
  preview, EXIF panel, QuickLook hookup, and "smart-select recommendation" badge
  is its own significant chunk of UX work. Cache + threshold-without-rescan ship
  first because they unblock the rest.
- **EXIF / codec metadata extraction.** The `metadata` table from the requirements
  schema doesn't exist yet (intentionally — adding empty schema for unimplemented
  features is just future churn). When the comparison view is built, add a v3
  migration creating `metadata` and a `MetadataExtractor` that uses ImageIO's
  `kCGImageProperty*` for photos and `AVAsset.load(.commonMetadata)` for videos.
- **Stage-2 perceptual matching: pHash only.** `PerceptualClusterer` queries on pHash
  and stores dHash for future use. The requirements doc suggests combining both for
  fewer false negatives; we'll re-evaluate with real-world data once the cache lets
  us A/B threshold strategies cheaply (Phase 4).
- **Stage-3 video matching limits.** Alignment window is ±5 frames — we miss matches
  where the same video has had its first 30 seconds clipped, etc. Full sequence-DP
  alignment (Smith-Waterman over per-frame Hamming) is the Phase-7 fix. Pairwise is
  also O(n²) on candidate count; for libraries with thousands of videos we'd want a
  per-frame BK-tree to prune. Both deferred until profiling on real libraries says
  the extra code is worth carrying.
- **Video format coverage gap.** AVFoundation only — MKV / AVI / WMV / WebM produce
  `unsupportedFormat` per-file. FFmpeg fallback is rejected for now (binary size,
  GPL licensing complexity, App-Store-friendliness even though we're direct-download
  for personal use). If a family member has e.g. an MKV archive, we'd revisit.
- **Debug-build hashing is slow.** SHA256 + DCT in unoptimised Swift takes ~50× longer
  than release. Always test against `swift build -c release` or `./build-app.sh` for
  realistic timing. (Discovered the hard way during Phase 2 smoke tests — debug-build
  CLI on 5-megapixel JPEGs hung apparently indefinitely; release ran in 0.4 s.)
- ~~**Launch-time backup auto-run.**~~ Resolved in Phase 4. `BackupRunner.runOnLaunchIfDue`
  is called from `PurpleDedupAppMain`'s WindowGroup `.task` modifier on first appear.
  Settings tab in `SettingsView` exposes the toggle, location picker, retention, and
  "run backup now". Same shape as Timeliner's reference impl.
- **TrashManager wiring.** `move(...)` works at the Core level; the GUI has no button
  for it yet. Phase 5 adds the Cleanup workflow (auto-select rules → mark → preflight
  modal → execute → log).
- **Live Photo pair atomicity.** Phase 1+2 treat each file independently. Phase 6.5
  (PhotoKit) will detect PHAsset Live-Photo subtypes and group still+video as one
  logical item. The current Phase 6 walks `.photoslibrary/originals/` directly
  and the existing `livePhotoCompanions` heuristic in CachedScanEngine catches
  the common case (same-stem .HEIC + .MOV in same folder).
- **iCloud Photos "Optimised Storage" gap.** When optimised storage is on,
  `.photoslibrary/originals/` files are placeholder stubs without actual bytes —
  ImageIO/AVFoundation fail per file. We log + continue; user must flip
  "Download originals to this Mac" in Photos.app for full coverage. Phase 6.5
  PhotoKit integration could read via PHAssetResourceManager which auto-fetches
  from iCloud, eliminating this gap.

## Where to start (next phase)

Phase 5 — Smart-select rules + cleanup workflow + undo. Concrete order:

1. **Rule chain engine** in `Sources/PurpleDedupCore/Selection/`. Types: `Rule`
   protocol, `RuleChain` of N rules, `Selection.recommend(cluster:rules:)` that
   returns one `keep` + N-1 `delete` per cluster with a reason string. Rules:
   highest-resolution / largest-size / smallest-size / newest-by-capture /
   oldest-by-capture / format-priority / folder-priority / most-metadata /
   shortest-path / longest-path / manual.
2. **Comparison-pane "KEEP" / "DELETE" badges** on each thumbnail. Phase 4.5
   already has the layout — just add a `Decision` overlay per file and a per-
   cluster reason caption.
3. **Per-cluster manual override** — let the user change the recommendation for
   one cluster without changing the rule chain.
4. **Pre-flight modal** before any destructive action: count, total size,
   breakdown by type, special-case Apple Photos library entries (which go to
   "Marked for Deletion" album, not Trash directly).
5. **`TrashManager` wired to GUI**: bulk Move-to-Trash, operation log
   pre-write so undo always has a record, restore-from-log via `FileManager
   .restoreItem` (or the modern equivalent).
6. **Edit > Undo** for the last operation.

The existing exclusion logic in `runPerceptualStage` / `runVideoStage` is the
template for any new stage that should skip files already in earlier clusters.
Cached fingerprints are now the source of truth for re-rendering UI without a
rescan — leverage `Database.fileWithFingerprint(at:)` instead of walking files.

## Test conventions

- All fixtures use real files in `FileManager.temporaryDirectory` (see
  `Tests/.../TestFixtures.swift`). Mocking `FileManager` would re-implement the engine
  with no extra confidence.
- Image fixtures are *generated* — `PerceptualHasherTests` and `PerceptualClustererTests`
  build CGImages in-memory (gradients, checkerboards) and write them to PNG via
  CGImageDestination. No checked-in binary blobs.
- `ContentHasherTests.testEmptyFileProducesKnownDigest` pins SHA256 of empty input.
  If you change the hash function, update this test *and* USER_MANUAL.md.
- `ExactClustererTests.testSizeBucketShortCircuit` verifies the all-unique-sizes case
  produces zero hashed candidates. If anyone reintroduces "hash everything," this
  catches it.
- `BKTreeTests.testCorrectnessAgainstBruteForce` random-checks the BK-tree against a
  linear scan over 200 hashes × 50 queries. If triangle-inequality pruning ever
  breaks, this is what'll surface it.
- `VideoClustererTests.testAlignmentRecoversOffsetSequence` pins the ±5-frame
  alignment window's correctness. Don't widen the window without re-running real-
  world tests — wider windows happily false-match unrelated content.
- `VideoClustererTests.testDurationGateExcludesVeryDifferentLengths` enforces the
  0.5-2.0 ratio gate. If we ever broaden it, expect more "trailer / full movie"
  false matches.
- Video tests use `TestVideo.build(...)` — a real AVAssetWriter pipeline, not a
  mock. If anyone "cleverly" replaces it with a stub, the fingerprinter no longer
  exercises real decode paths and will silently regress.
- `PerceptualClustererTests.testExactDupesNotDoubleReportedAsSimilar` — perceptual
  clusters must exclude files already in an exact cluster. If the exclusion is
  removed, every byte-identical pair would re-appear as also-similar, which is
  technically true but useless. Keep this test.
- `BackupServiceTests.testTrimRespectsRetentionAndPrefix` ensures the trim only
  touches files prefixed `PurpleDedup-`. PhantomLives convention; do not weaken.
