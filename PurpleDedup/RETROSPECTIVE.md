# PurpleDedup — Project Retrospective

Current version: **0.22.3** (first notarized release)
Retrospective date: 2026-05-10

---

## What shipped

PurpleDedup is a native macOS duplicate-file finder with deep Apple Photos integration. In a single rapid development sprint it grew from a bare scaffold to a feature-complete app covering the entire original requirements document plus a long tail of user-driven additions.

### Feature timeline

| Version | Date | Milestone |
|---|---|---|
| 0.1.0 | 2026-05-09 | Foundation: three-target SwiftPM, exact hashing, GRDB cache, backup service, CLI |
| 0.2.0 | 2026-05-09 | Perceptual photo matching (pHash + dHash, BKTree, UnionFind) |
| 0.3.0 | 2026-05-09 | Video fingerprinting (AVFoundation, sequence alignment) |
| 0.4.0 | 2026-05-09 | CachedScanEngine, session persistence, launch-time backup |
| 0.4.1 | 2026-05-09 | Hotfix: APFS case-collision rename CLI → `pdedup` |
| 0.5.0 | 2026-05-09 | Hash speed, thumbnails, app icon |
| 0.5.1 | 2026-05-09 | Embedded-thumbnail decode speedup; Live Photo MOV skip; Quick Look fix |
| 0.6.0 | 2026-05-09 | **5.2× scan speed** (frame cap + parallel stages + bulk cache load) |
| 0.7.0 | 2026-05-09 | Three-pane comparison UI; EXIF/codec metadata table with diff highlighting |
| 0.8.0 | 2026-05-09 | Smart-select rule chain; pre-flight modal; Trash + Cmd+Z undo |
| 0.9.0 | 2026-05-09 | Photos library read-only scan support |
| 0.10.0 | 2026-05-09 | Session persistence; bulk "Apply to all" / "Clear overrides"; drag-drop fix |
| 0.11.0 | 2026-05-09 | Keyboard review flow (⌘↑/↓/⏎); burst-series detection |
| 0.12.0 | 2026-05-09 | Granular trash; custom rule chain + folder priority; Settings → Rules |
| 0.13.0 | 2026-05-09 | Session resume across launches; opt-in notarization gate in build script |
| 0.14.0 | 2026-05-09 | PhotoKit "Marked for Deletion" album round-trip |
| 0.15.0 | 2026-05-09 | Rotated-copy detection; stage-folder destination; dry-run plan export |
| 0.16.0 | 2026-05-09 | Photos metadata in comparison pane; cross-source cluster highlighting |
| 0.17.0 | 2026-05-09 | Per-library scan filter (albums, subtypes, favorites, hidden) |
| 0.18.0–0.18.4 | 2026-05-09 | Photos entitlement + TCC reset; Tahoe layout recovery; hidden-only filter via direct Photos.sqlite read; cancel + Force Quit watchdog |
| 0.19.0 | 2026-05-09 | People filter; reverse-geocoded GPS; dHash OR-merge; In-Photos badge for non-exact clusters; CLI Photos filter flags |
| 0.20.0 | 2026-05-09 | Sparkle 2.9 in-app auto-updates + `Scripts/release.sh` pipeline |
| 0.21.0 | 2026-05-09 | FFmpeg sidecar for MKV/AVI/WMV/WebM (opt-in, avoids GPL bundling) |
| 0.21.2–0.21.3 | 2026-05-10 | Reclaimable-bytes metric; cluster-kind chip filters; dark-mode polish |
| 0.22.0 | 2026-05-10 | Cluster-row redesign; Smith-Waterman video alignment; ContentView decomposition (−24%, 11 new files) |
| 0.22.1 | 2026-05-10 | Cancel reliability fix (ScanCoordinator checkpoints + cancelTick SwiftUI state) |
| 0.22.2 | 2026-05-10 | PhotoKit metadata cache thrashing fix (shard-aware library fingerprint) |
| 0.22.3 | 2026-05-10 | First notarized release (notarytool keychain profile + staple in release.sh) |

### Test growth

| Phase | Tests |
|---|---|
| 0.1.0 (foundation) | 18 |
| 0.3.0 (+video) | 44 |
| 0.5.0 (+perf) | 47 |
| 0.8.0 (+selection) | 59 |
| 0.11.0 (+burst/keyboard) | 69 |
| 0.15.0 (+rotated/stage/dry-run) | 80 |
| 0.19.0 (+people/OR-merge) | 95 |
| 0.21.0 (+FFmpeg) | 98 |

---

## What went well

### Architecture decisions that held up

**Three-target SwiftPM from day 1.** Separating `PurpleDedupCore` / `PurpleDedupApp` / `PurpleDedupCLI` meant the engine could be tested and iterated without a GUI, the CLI could validate correctness, and the GUI got the same code for free. No refactoring of the seam was ever needed.

**Actor-based concurrency model.** `CachedScanEngine` as an `actor`, `PhotoKitDeletionService` as an `actor` — both turned out exactly right. The engine's actor boundary made `Task.isCancelled` cancel propagation straightforward. PhotoKit's own callbacks aren't re-entrant-safe; the actor prevents the deadlock that would have emerged under concurrent album mutations.

**BKTree + UnionFind design.** The Burkhard-Keller tree on Hamming distance gives sub-linear neighbor search at the thresholds we care about. Transitive clustering via UnionFind is correct and fast. Both primitives were designed once, tested once, and never touched again despite multiple new clustering algorithms layering on top (burst, rotated).

**Embedded-thumbnail decode.** Switching `PerceptualHasher` from `CreateThumbnailFromImageAlways` to `CreateThumbnailFromImageIfAbsent` cut photo perceptual hash time by an order of magnitude. This is the same technique Gemini uses; recognizing it early was the biggest single performance win short of the frame cap.

**GRDB for the cache.** Bulk-loading all rows in one `SELECT * FROM files JOIN fingerprints` at scan start eliminated thousands of per-file SQLite round-trips. The decision to use batched write transactions (one per stage, not one per file) was easy to retrofit because GRDB's API makes batching natural.

**Generated test fixtures.** No binary test blobs in the repo. `PerceptualHasherTests` and friends build CGImages and videos programmatically (gradients, checkerboards, AVAssetWriter H.264). This kept the repo clean, made fixture generation reproducible, and avoided the subtle "this PNG was generated on a different OS" failure class.

### Delivery pace

The core requirements document was fully covered in the first sprint (0.1.0–0.15.0, all in one day), with a long tail of user-driven additions (Photos metadata, People filter, FFmpeg, Sparkle, Smith-Waterman) that arrived in the second sprint. Deferring BLAKE3, Stage-2 partial hashing, and a per-frame BK-tree for video was the right call — none of them were bottlenecks on real hardware.

---

## What was harder than expected

### APFS case-insensitive binary collision (0.4.1)

The SwiftPM products `PurpleDedup` (GUI) and `purplededup` (CLI) collided at the same bin-path on APFS case-insensitive volumes. The CLI was silently overwriting the GUI binary; `build-app.sh` then bundled the CLI as the app, causing every double-click to print `Error: At least one path is required` and exit. The fix (rename CLI to `pdedup`) is simple in hindsight but was completely invisible during development — the build log showed success and the binary landed in `.build/` exactly as expected. The `otool -L` ArgumentParser check added to `build-app.sh` as a regression trap is the right permanent fix.

**Lesson:** On APFS case-insensitive volumes, product names must be globally unique, not just unique within one target. Verify with `ls -li` that two supposedly-distinct binaries aren't the same inode.

### VTDecoderXPCService wedge (0.6.0)

The first real-world performance run on a 4,038-file / 57 GB library took 100 s, vs Gemini's ~15 s. Profiling with `sample` revealed every worker thread was parked in `VTTileDecompressionSessionDecodeTile` waiting on a hung XPC reply. Root cause: killing `pdedup` with SIGKILL during earlier dev sessions left orphaned `VTDecoderXPCService` processes holding stale XPC endpoints. Subsequent launches inherited the broken decoder.

**Lesson:** Never `pkill -9` during video stage dev. Recovery is `killall VTDecoderXPCService`. The parallel-stage frame-cap fix that brought the scan time to 19 s would have landed in a single step rather than chasing a ghost performance problem, had we understood the environment contamination earlier.

### Tahoe (macOS 26) layout breakage (0.18.x)

Three distinct SwiftUI/AppKit bugs on Tahoe hit in rapid succession:

1. `NSSplitViewItem` reporting ~2× content height in `NavigationSplitView`'s sidebar, pushing the sources strip off-screen.
2. `.sheet(item:)` and `.popover(isPresented:)` both rendering as empty white boxes inside a `GeometryReader`-wrapped NSSplitViewItem column.
3. Stale `NSSplitView Subview Frames` UserDefaults poisoning the next launch's geometry even after fixing the live layout.

Each bug required a separate workaround (`GeometryReader` force-fit; inline filter editor; launch-time UserDefaults purge). The combination consumed most of the 0.18.x release bandwidth.

**Lesson:** On a new OS, validate the primary layout and all modal surfaces (sheets, popovers) before building features on top of them. A one-time Tahoe smoke test of a bare `NavigationSplitView` would have exposed the height bug and the sheet bug before any feature code went in.

### PhotoKit privacy gate complexity (0.18.x)

What started as "integrate Photos library scanning" turned into a multi-release arc of privacy-gate surprises:

- **Silent TCC deny without OS prompt:** Without `com.apple.security.personal-information.photos-library` in the entitlements file, every `requestAuthorization` call returns `.denied` instantly, the OS never shows the user a prompt, and the app never appears in System Settings → Photos. The user has no visible path to grant access.
- **Locked Hidden Album:** macOS 14+ refuses to surface `asset.isHidden == true` to third-party apps even with full library access granted. The only workaround is to read `Photos.sqlite` directly.
- **UUID-named files:** Photos stores `originals/<shard>/<UUID>.<ext>` on disk, not `<OriginalFilename>.<ext>`. Filter resolution that returns original filenames matches zero on-disk files. The UUID-stem matching in `FileWalker` was the fix; finding it required digging into the Photos bundle layout.
- **Shard cache thrashing:** The PhotoKit metadata cache keyed on the parent directory of each file, which changes with every `originals/` shard transition (16 subdirs by UUID first char). Every cluster click in a multi-shard library triggered a full PHAsset enumeration. Only visible with a large library and patient profiling.

**Lesson:** PhotoKit on macOS 14+ is significantly more restrictive and quirky than the API surface suggests. Budget extra time for every Photos-integration feature, and test against a real large library, not a synthetic small one.

### Cancel reliability was non-trivial (0.22.1)

The 0.18.4 cancel implementation checked `Task.isCancelled` in the engine drain loops, which worked well for the compute stages. Two separate bugs emerged later:

1. `ScanCoordinator.resolveSources` ran all per-source PhotoKit fetches without any cancel checkpoints, so a pending cancel could sit un-serviced until the entire source list resolved.
2. The Force Quit button's "show after 4 s" condition was a `Date().timeIntervalSince(...)` evaluated during body render — but SwiftUI only re-renders body when `@State` changes, and a stuck PhotoKit fetch emits zero events. Force Quit never appeared.

**Lesson:** Cancel propagation in an async system requires checkpoints at every "call that can block for seconds," not just at loop boundaries. UI timers that depend on external events need their own heartbeat `@State` rather than relying on event-driven re-renders.

---

## Architecture notes for the next phase

### What to carry forward

- The three-stage pipeline (`exact → perceptual → video`) with per-stage `[STAGE x] Ns` timing is the right mental model. New clustering algorithms should slot in as additional stages in `CachedScanEngine`, reusing the existing `excludeURLs` exclusion pattern.
- `Database.fileWithFingerprint(at:)` is the right way to re-render UI without a rescan. Avoid re-walking files.
- `PhotoKitDeletionService` as an `actor` is the right home for all Photos.sqlite direct reads, not just album operations.

### Known gaps worth revisiting

- **Pairwise video matching is O(n²).** Fine for libraries with hundreds of videos; breaks for thousands. A per-frame BKTree would prune the candidate set before the O(n²) alignment.
- **iCloud Optimised Storage.** The `originals/` walker hits placeholder stubs and logs errors per file when optimised storage is on. The fix is a PhotoKit-enumeration-first pass that only walks files it knows are local, which would require replacing the `FileWalker` entry point for Photos sources.
- **Unnamed faces in People filter.** `ZPERSON.ZFULLNAME / ZDISPLAYNAME` is empty for unnamed face groups. Surfacing them by face cluster rather than by name would require reading `ZASSETFACEFEATURE` embedding coordinates, which is a different problem than text matching.
- **ContentView is still large.** The 0.22.0 decomposition brought it from 2150 → ~1640 lines. The remaining mass is mostly the scan-coordination state machine; extracting it as a proper `@Observable` model would bring it under control and make the state transitions testable.

---

## Metrics summary

| Metric | Value |
|---|---|
| Versions shipped | 0.1.0 – 0.22.3 (30 releases) |
| Tests | 18 → 98 (5.4× growth) |
| ContentView LOC | ~2150 → ~1640 (after decomposition) |
| New source files | 40+ across Core + App |
| Scan speed improvement | 100 s → 19 s (5.2×) on 4K-file / 57 GB library |
| Warm scan speed | ~0.23 s (cache hot) |
| First notarized release | 0.22.3 (2026-05-10) |
