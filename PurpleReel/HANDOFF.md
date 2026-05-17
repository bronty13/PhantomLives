# PurpleReel — Architecture Handoff

> First read on every new working session. Keep this file current with
> material architecture changes.

## What it is

A native macOS SwiftUI app for media management focused on Final Cut Pro:
Finder-aware browser, AVKit player with frame-accurate transport + LUT
preview, marker/subclip/tag/rating logging, batch transcode (native +
ffmpeg), verified backup with industry-standard MHL XML, FCPXML export
and `open -a` hand-off, SFTP delivery, and three on-device AI flows
(MLX-Whisper transcription, Ollama auto-description, perceptual
similar-takes). All processing local; nothing leaves the machine.

Built with the PhantomLives conventions: XcodeGen + GRDB + standardized
`build-app.sh` / `install.sh`, auto-backup on launch, `~/Downloads/`
output, `WindowStateGuard` for any nested split views, manual
`HStack` for the top-level sidebar (NOT `NavigationSplitView` — see
top-level `CLAUDE.md`).

## Architecture at a glance

- **`AppState`** (`@MainActor ObservableObject`) — top-level store.
  Owns the asset list, selection state, the detail slices for the
  current selection (`markers`, `subclips`, `tags`, `rating`,
  `transcript`), every sheet-visibility bool, and the
  `transcodeQueue`. Mutations go
  `View → appState.method() → DatabaseService → reload<slice>()`.
  All AI actions read settings overrides from `UserDefaults` at call
  time and emit a `aiSheetState: AISheetState?` for the unified AI
  sheet.
- **`DatabaseService`** (class, eager-init from `AppState.init`) —
  sole owner of the GRDB `DatabaseQueue` at
  `~/Library/Application Support/PurpleReel/purplereel.sqlite`.
  Schema in a single `v1_schema` migration: `asset`, `tag`,
  `asset_tag`, `marker`, `subclip`, `rating`, `transcript`, plus an
  FTS5 virtual table `asset_fts` over filename/description. CRUD
  methods are thin and explicit; transcript I/O round-trips
  `TranscriptDocument` through JSON column storage.
- **`BackupService`** (enum) — the PhantomLives auto-backup hook.
  `runOnLaunchIfNeeded` is called from `AppState.init`, debounces
  (5-min minimum gap via `lastBackupAt` defaults key), zips the
  Application Support directory to
  `~/Downloads/PurpleReel backup/PurpleReel-<stamp>.zip`, trims
  archives older than `backupRetentionDays` (default 14).
- **`WindowStateGuard`** (enum) — preflight + versioned reset. Wired
  from `AppDelegate.applicationWillFinishLaunching`. Strips
  `NSSplitView Subview Frames *` keys + the bundle's `.savedState`
  directory whenever a stale frame key is found; one-shot full
  window-state reset triggered by bumping
  `AppDelegate.windowResetVersion`. Reference implementation cited
  in the top-level `CLAUDE.md` "Sidebar layout" section.

## Service inventory

All `Sources/PurpleReel/Services/`. Each is a single-responsibility
type with a narrow public API; the `View` layer doesn't talk to
`AVFoundation` / `CryptoKit` / `Foundation.URLSession` directly.

| Service | Role |
|---|---|
| `MediaScanner` (actor) | Recursive Finder walk → `[Asset]` with codec/res/fps/duration via `AVURLAsset.load(.*)`. |
| `Timecode` (enum) | SMPTE non-drop `HH:MM:SS:FF` formatter; frame-duration math for J/L shuttle. |
| `LUTService` (enum) | Adobe `.cube` parser (3D native, 1D synthesized into 33³). Produces `CIColorCubeWithColorSpace` filter for `AVVideoComposition`. |
| `WaveformService` (enum) | AVAssetReader 16-bit PCM pass → 800-bucket peak array under a sqrt curve. Renders behind the scrubber. |
| `ThumbnailService` (enum) | 12 frames per video (middle 90% to skip slates/leader), JPEG-cached at `~/Library/Application Support/PurpleReel/thumbnails/<path+mtime sha256>/`. |
| `TranscodeService` (enum) + `TranscodeJob` (`@MainActor` class) + `TranscodeQueue` (`@MainActor` class) | Serial-drain queue. Native presets via `AVAssetExportSession`; Phase-2 presets (DNxHR SQ/HQ, Cineform, MXF rewrap) shell out to `ffmpeg` and parse `time=HH:MM:SS.xx` from stderr. |
| `HashingService` (enum) | CryptoKit `Insecure.SHA1` / `Insecure.MD5` / `SHA256` over 4 MB chunks. Bit-for-bit verified against system `shasum`. |
| `MHLWriter` (enum) | ASC Media Hash List v1.1 XML. Pure-string builder; XML-escapes all attribute values. |
| `VerifiedBackupService` (enum) | Walk source → hash → copy + verify against 1–4 destinations in parallel via `TaskGroup` → emit one MHL per destination. Hash mismatches fail the file individually. |
| `FCPXMLWriter` (enum) | Final Cut Pro XML v1.10. Dedupes `<asset>`/`<format>`, snaps timing to the asset's frame grid using NTSC-correct rationals, file paths percent-encoded **and** XML-escaped (caught by tests). |
| `SFTPService` (enum) + `SFTPJob` (`@MainActor` class) | Streams stdout from `/usr/bin/sftp -b <batch>`, parses `Uploading … to …` and `100% …` lines for live per-file progress. Optional `sshpass -e` for password auth via `SSHPASS` env (not `-p`). |
| `KeychainService` (enum) | `SecItem*` wrapper. Per-destination SFTP passwords under service `com.bronty13.PurpleReel.sftp` keyed by destination UUID. |
| `WhisperService` (enum) | Spawns sibling `transcribe/transcribe.py` with `-i -o -f srt -m <model>`. Pure `parseSRT(_:)` exposed for testing. Persists `TranscriptDocument` JSON. |
| `OllamaService` (enum) | `POST localhost:11434/api/generate` (1-second reachability probe + live `/api/tags` model list). Stream off for single-JSON response; prompt template combines filename + transcript snippet. |
| `SimilarTakesService` (enum) | dHash middle frame (8×9 grayscale, adjacent-pixel comparison → UInt64) → BKTree cluster via Hamming. |
| `BKTree` (class) | Burkhard-Keller metric tree with triangle-inequality pruning at each level. Verified equivalent to brute force on 500-element synthetic sets at 4 thresholds. |
| `BatchRenameService` (enum) | Token-template expansion (`{orig}` `{date[:fmt]}` `{counter[:N]}` `{codec}` `{fps}` `{w}` `{h}` `{size_mb}` `{ext}`), preview-with-conflict-detection, on-disk move + catalog update. |

## View tree

- **`PurpleReelApp`** (`@main`) — wires `AppState`, `AppDelegate` adaptor,
  toolbar's `Window → Reset Window State…` command, `Settings` scene.
- **`ContentView`** — **`HStack`** with optional 240px sidebar +
  `BrowserView`. Hosts the 9 toolbar items (Toggle Sidebar, Open
  Folder, Rescan, AI menu, Batch Rename, SFTP, Backup, Transcode menu,
  Send-to-FCP menu) and 5 sheets (transcode queue, backup, sftp, ai
  state, batch rename).
- **`BrowserView`** — `VSplitView` with `Table(assets, selection:)` on
  top (thumbnail / name / codec / res / fps / duration / size columns)
  and an `HSplitView` detail (`PlayerView` left, detail panes right)
  when an asset is selected. Wraps `PlayerController` as
  `@StateObject`.
- **Player surface**: `PlayerView` hosts `PlayerSurface`
  (`NSViewRepresentable` with `AVPlayerLayer`), `Scrubber`
  (waveform-aware, I/O overlay, click-to-seek), transport bar with
  multi-rate J/K/L shuttle, LUT bar.
- **Detail panes**: `MarkersListView`, `SubclipsListView`,
  `TagsRatingView`. Each binds to `appState.markers` / `.subclips` /
  `.tags` / `.rating`.
- **Sheets**: `TranscodeQueueView`, `BackupView`, `SFTPDeliveryView`,
  `AISheetView` (state enum-driven), `BatchRenameView`, `SettingsView`
  (Backup / AI / About tabs).
- **`ThumbnailCell`** — 80×45 lazy cell, cycles 12 frames on
  `onContinuousHover`.

## Tests

```sh
./run-tests.sh
```

28 unit tests across 8 files. Coverage map:

| File | Coverage |
|---|---|
| `BatchRenameTests` | 6 cases: token expansion (orig/ext/date/counter/codec/fps/technical), unknown-token preservation, within-batch collision detection. |
| `HashingTests` | 6 cases: FIPS 180-4 vectors for SHA-1/MD5/SHA-256 (empty + "abc"), chunked-matches-single-shot on 9 MB pseudo-random data, progress callback total. |
| `MHLWriterTests` | 2 cases: XML well-formedness round-trip through `XMLDocument`, special-char escape, per-algorithm element name (sha1/md5/sha256). |
| `FCPXMLWriterTests` | 5 cases: well-formedness, NTSC format selection at 29.97, marker/subclip/tag/rating render, XML escape of attribute values + percent-encoding of paths, low-rating no-Favorite. |
| `WhisperSRTTests` | 5 cases: basic shape, multi-line body, CRLF endings, millisecond timestamp precision, empty input. |
| `WindowStateGuardTests` | 2 cases: split-view key sweep, window-frame keys survive preflight. |
| `BKTreeTests` | 4 cases: exact-match, within-threshold set membership, brute-force agreement on 500 synthetic hashes at 4 thresholds, insertion count. |
| `SmokeTests` | 1 case: `AssetKind.from(extension:)`. |

## Build / install / version

```sh
./build-app.sh && ./install.sh
```

- `build-app.sh` regenerates the icon (`Scripts/generate-icon.swift` →
  asset catalog), runs `xcodegen generate`, derives
  `CFBundleShortVersionString = 0.1.<commit-count>` and
  `CFBundleVersion = <count>.<short-sha>`, builds Release in
  `mktemp -d`, signs (Developer ID Application if a cert is in the
  keychain, ad-hoc otherwise).
- `install.sh` quits any running copy via osascript, `ditto
  --noextattr` to `/Applications/PurpleReel.app`, relaunches via
  `open`. `--no-open` skips the relaunch.

## Output paths

| What | Where |
|---|---|
| Catalog DB | `~/Library/Application Support/PurpleReel/purplereel.sqlite` |
| Settings | `UserDefaults` (`com.bronty13.PurpleReel`) |
| SFTP passwords | macOS Keychain, service `com.bronty13.PurpleReel.sftp` |
| Thumbnail cache | `~/Library/Application Support/PurpleReel/thumbnails/` |
| Auto-backup zips | `~/Downloads/PurpleReel backup/PurpleReel-<stamp>.zip` (14-day retention by default) |
| Transcodes | `~/Downloads/PurpleReel/transcoded/` |
| FCPXML exports | `~/Downloads/PurpleReel/exports/` |
| MHL manifests | alongside the backed-up files inside each destination |

## Cross-cutting conventions

- **No `NavigationSplitView` at the top level** — see top-level
  `CLAUDE.md` "Sidebar layout" section. Manual `HStack` with
  fixed-width sidebar. `WindowStateGuard` for any nested
  `HSplitView` / `VSplitView`.
- **App icon wired before first build** — film reel on purple
  gradient via `Scripts/generate-icon.swift`. Runs every build so
  edits to the generator land without manual round-trip.
- **All AI processing is on-device** — Whisper runs the local MLX
  pipeline, Ollama is `localhost:11434`, perceptual hashing is pure
  Swift. No telemetry, no cloud round-trips.
- **Sandbox is off** — see entitlements file. Personal app reading
  arbitrary user paths; TCC grants stick because `install.sh` always
  lands at `/Applications/PurpleReel.app`.
- **Sibling project dependencies**: `transcribe/` is the canonical
  source of truth for MLX Whisper. PurpleReel doesn't vendor any of
  the Python; it bridges via `Process`.
