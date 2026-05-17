# PurpleReel Changelog

## Unreleased — Kyno-parity round 2 (workspace, history, full menu bar)

- **Workspace = multiple roots** (was: single rootFolder). `Open
  Folder…` replaces the workspace; new **Add Folder to Workspace…**
  (⌘I) extends it. Sidebar renders one folder tree per root with
  a context menu (Remove from Workspace / Reveal in Finder), a
  Workspace header gear-menu (Add Folder / Clear Workspace), and
  persists across launches.
- **Bug fix**: opening a different folder no longer leaves the
  previous folder's clips visible. `displayedAssets` now always
  filters by either the explicitly-selected folder or — when no
  folder is selected — the union of all workspace roots.
- **History navigation**: ⌘[/⌘] back/forward through folder
  selections, with a History menu plus back/forward arrow buttons
  in the browser toolbar. The History → Clear History menu wipes
  the stack but keeps the current location.
- **Comprehensive Kyno-style menu bar**: File / Edit / Playback /
  Metadata / Convert / View / History / Window / Help, mirroring
  the reference screenshots. Wires every action that already
  exists (Open, Add Folder, Reveal, Rename, Export Subclips/
  Metadata, Copy and Verify [opens Verified Backup], Playback
  shortcuts, Rating ⌘0…⌘5, Transcribe / Auto-Describe / Similar
  Takes, every Transcode preset including ffmpeg, Previous/Next
  Clip ⌘←/⌘→, Drilldown ⌘D, Back/Forward ⌘[/⌘], Reset Window
  State, Keyboard Shortcut Reference). Menu items routed to the
  player (loop, in/out, markers, export frame, in-to-out) post
  `Notification.Name.playerCommand` so the menu drives the same
  pipeline as the existing keyboard handler.
- **Previous/Next Clip** (⌘← / ⌘→) — moves the asset selection up
  or down one row within the current displayed list. Wraps to
  start/end at boundaries.
- New `KYNO_PARITY_ROADMAP.md` tracks the complete gap from Kyno
  with ✅ / 🟡 / ⬜ status per item.

## Unreleased — Kyno-parity round 1 (Content/Tracks tabs, folder tree, browser controls)

User-driven; replicating the parts of Kyno's UX that close the most
visible gaps. Working from Kyno reference screenshots + the support
keyboard-shortcuts reference page.

- **Content tab** (`ClipContentView`): file metadata block (filename,
  path, size, modification/recording date, container, codec, fps,
  bitrate, audio codec/rate/channels) stacked above a 5×6 = 30-frame
  grid. Each tile shows the seconds offset overlay and is clickable
  to seek the player. `ClipDetailsService` pulls the extended
  metadata from `AVURLAsset` on demand.
- **Tracks tab** (`ClipTracksView`): per-stream technical breakdown
  matching Kyno's Tracks view — Track #1 (video) with codec / fps /
  resolution / aspect / bitrate / duration; Track #2 (audio) with
  codec / sample rate / channel layout / bitrate. Loads lazily on
  appear.
- **`ThumbnailService` parameterized**: accepts a frame count;
  hover-scrub cell still uses 12, the Content grid uses 30. Cache
  dir hash now includes the count so different counts cohabit.
- **Player View menu**: Rotate (0/90/180/270) + Flip H/V applied as
  a `CALayer.setAffineTransform` on `AVPlayerLayer`. Preview-only —
  the underlying file and any transcode are untouched.
- **Folder tree sidebar + drilldown**: recursive `FolderNode` tree
  built from the asset list's paths; expandable rows with disclosure
  triangles, recursive asset count badges. Selection drives a
  `displayedAssets` filter on AppState. Drilldown toggle in the
  browser toolbar controls whether subfolder contents are included.
- **Type filter chips**: All / Video / Audio / Images, capsule
  buttons in the browser toolbar.
- **Sort dropdown**: Name / Date / Size / Duration / FPS, persisted
  in `@AppStorage`. Drives the `displayedAssets` sort order.

## Unreleased — Round 2 follow-ups (thumbnails, SFTP pwd, BK-tree)

- **Thumbnail strip with hover-scrub** in the browser:
  `ThumbnailService` generates 12 evenly-spaced JPEGs per video
  (spread over the middle 90% to skip slates/leader), JPEG-encoded
  at 240px max, cached under
  `~/Library/Application Support/PurpleReel/thumbnails/<hash>/`.
  Cache key includes file modification time so touching the source
  invalidates. `ThumbnailCell` is the SwiftUI view: lazy-loads the
  middle frame on appear, cycles frames based on cursor X under
  `onContinuousHover`, falls back to a film icon when frame
  extraction fails. Added as the leftmost (90px) column of the
  asset table.
- **SFTP password auth** via `sshpass` + Keychain:
  `KeychainService` wraps `SecItem*` for per-destination password
  storage keyed by the destination's UUID. `SFTPService` detects
  `sshpass` (Homebrew or system path); when a password is stored
  for the active destination, sftp is launched as
  `sshpass -e /usr/bin/sftp …` with the password injected via the
  `SSHPASS` env var (safer than `-p` which would expose it in
  `ps`). UI gets a SecureField + a green/orange status line
  indicating whether sshpass is installed.
- **BK-tree similar-takes clustering**: replaces the previous
  O(n²) pairwise loop. `BKTree.swift` is the Burkhard-Keller tree
  with triangle-inequality pruning at each level. Scales us up to
  tens of thousands of clips without changing the
  `SimilarTakesService.findClusters` API. Verified against
  brute-force on 500 synthetic UInt64 hashes at four thresholds
  (2, 8, 20, 64) — results agree exactly.
- **Tests**: +4 BK-tree tests (exact match, within-threshold
  set membership, brute-force agreement, insertion count). All
  28 tests still green.

## Unreleased — Post-MVP follow-ups

- **XCTest suite** (24 tests across 6 files, `./run-tests.sh`):
  BatchRenameService token expansion, HashingService SHA-1/MD5/SHA-256
  against canonical FIPS vectors + chunked-matches-single-shot,
  MHLWriter XML well-formedness + escape, FCPXMLWriter
  well-formedness + special-chars escape, WhisperService.parseSRT
  shape coverage, WindowStateGuard preflight semantics.
- **FCPXMLWriter bug fix** caught by the new tests: `file://` URLs
  with `&` in the path were emitted unescaped, breaking XML parse.
  `fileURL()` now percent-encodes and XML-escapes.
- **Settings → AI pane** (`AISettingsView`): override `transcribe.py`
  path, pick Whisper model (turbo/tiny/base/small/medium/large-v3),
  pick Ollama model from live `/api/tags` query with reachability +
  script-presence indicators. Persisted via `@AppStorage`.
- **AI service overrides plumbed** through `transcribeSelected` and
  `autoDescribeSelected` — settings take effect immediately.
- **Per-byte SFTP progress**: streaming stdout parser hops on the
  main actor as sftp emits `Uploading <path> to <name>` / `100% …`
  lines, updating `SFTPFileItem.state` live. Raw log accumulates in
  real time too instead of all-at-end.
- **Parallel multi-destination backup**: when ≥2 destinations are
  configured, copy + verify happen concurrently via `TaskGroup`.
  Source hash still computed once per file. Wall time ~= slowest
  destination (was: sum across destinations).
- **Phase-2 codecs via ffmpeg** (4 new presets): DNxHR SQ, DNxHR HQ,
  Cineform, and ProRes-in-MXF rewrap. `TranscodeJob.runFFmpeg`
  shells out to `ffmpeg`, parses `time=HH:MM:SS.xx` from stderr to
  drive the progress bar, surfaces a clear error if ffmpeg isn't
  installed.

## Unreleased — Phase 11-12: polish + docs

- **Audio waveform overlay**: `WaveformService` runs an AVAssetReader
  pass over the first audio track at file-load time, bucketing
  16-bit PCM into 800 peak amplitudes (Accelerate-friendly inner
  loop, sqrt curve so dialog stays visible against transients).
  Renders behind the scrubber playhead via a custom `WaveformShape`.
- **Multi-rate J/K/L shuttle**: J/L step through ±¼× / ±½× / ±1× /
  ±2× / ±4×. Direction-reverse resets to 1× in the new direction
  (FCP/Premiere semantics). K stops.
- **Batch rename** with token template (`{orig}` `{ext}` `{date[:fmt]}`
  `{counter[:width]}` `{codec}` `{fps}` `{w}` `{h}` `{size_mb}`),
  live preview with red-flag conflict detection, on-disk move +
  catalog DB path update + auto-rescan.
- **USER_MANUAL.md**: full feature reference — install, keyboard,
  toolbar, logging, LUT, transcode, backup+MHL, SFTP, FCPXML, all
  three AI flows, batch rename, output paths, recovery.

## Unreleased — Phase 9-10: AI augmentation

All three differentiators that make this not-a-Kyno-clone, fully local
(nothing leaves the machine):

**Whisper transcription** (`WhisperService`):
- Bridges the sibling `transcribe/` MLX-Whisper project via Process.
- Probes for Homebrew Python (3.10+) first, falls back to `/usr/bin/python3`.
- Runs `transcribe.py -i <file> -o <tmp> -f srt --quiet -m turbo`,
  parses the produced SRT into `[TranscriptSegment]` (verified parser
  against synthetic SRT).
- Persists `TranscriptDocument` JSON in the existing `transcript`
  table; surfaces a segment-by-segment reader in the AI sheet.
- "Transcribe + Create Markers" option auto-emits one marker per
  segment with the transcribed text as the marker note.

**Ollama auto-description** (`OllamaService`):
- HTTP POST to `localhost:11434/api/generate` with `stream:false`.
- Round-trip verified live against `dolphin-mistral:latest`.
- Reachability probe (`/api/tags`, 1s timeout) — fast fail when
  Ollama isn't running.
- Prompt assembled from filename + (if present) transcript snippet;
  result lands in the asset's description field.

**Similar takes** (`SimilarTakesService`):
- 64-bit dHash (8×9 luminance grid, adjacent-pixel comparison) of
  each video's middle frame — deterministic, verified across repeated
  runs.
- Naive O(n²) pair-wise Hamming clustering with union-find at
  threshold 10/64 bits. Adequate for hundreds of clips; BK-tree port
  is a Phase-2 optimization.
- Per-cluster "best" pick: highest rating → longest duration →
  filename tiebreak. Surfaces in the AI sheet with a rationale.

**UI:**
- New "AI" sparkles menu in the toolbar (Transcribe / Auto-Describe /
  Find Similar Takes).
- Unified `AISheetView` sheet handles all three flows via an
  `AISheetState` enum (progress / ready / error).

## Unreleased — Phase 8: SFTP delivery

- `SFTPDestination` model + `SFTPDestinationStore` (JSON-backed
  UserDefaults persistence). Multiple named destinations.
- `SFTPService` shells out to `/usr/bin/sftp` with a generated batch
  script (`-mkdir` + `cd` + `put` per file + `bye`); captures stdout
  + stderr, parses per-file success/failure into `SFTPFileItem` state.
  Command construction dry-run-verified against expected CLI form.
- `SFTPDeliveryView` sheet: 220px destinations list (add / duplicate /
  delete), grouped editor form (host / port / user / remote path /
  identity-file / accept-new-host-keys), file picker (add from disk
  or "all catalogued"), per-file progress, raw `sftp` log disclosure.
- Auth model: SSH key only for MVP (use ssh-agent / `~/.ssh/config`,
  or an explicit identity-file path). Password auth deferred —
  requires `sshpass` and Keychain integration.
- `com.apple.security.network.client` added to entitlements
  (defensive; sandbox is off so not strictly required).

## Unreleased — Phase 8: FCPXML export

- `FCPXMLWriter`: emits well-formed FCPXML v1.10 (validates with
  `xmllint`). Per-asset `<asset>` + `<format>` dedup, rational-time
  math snapped to the asset's frame grid (uses canonical NTSC
  timescales 24000/30000/60000 for 23.98/29.97/59.94 and 100-based
  for 24/25/30/50/60). Logged markers, subclips, tags, and 4–5 star
  ratings cross over to the FCP timeline as `<marker>`, `<asset-clip>`
  with explicit `start`/`duration`, `<keyword>` (tags joined), and
  `<rating name="Favorite">`.
- Send-to-FCP toolbar menu: send selected clip, send entire library,
  with/without auto-launch of `/Applications/Final Cut Pro.app`.
  Falls back to Finder reveal when FCP isn't installed.
- Output lands in `~/Downloads/PurpleReel/exports/`.

## Unreleased — Phase 7: verified backup + MHL

- Chunked streaming hasher (`HashingService`): CryptoKit-backed SHA-1,
  MD5, SHA-256. 4 MB chunks. Cross-validated bit-for-bit against
  system `shasum`.
- Industry-standard ASC Media Hash List v1.1 writer (`MHLWriter`):
  `<hashlist>` with `<creatorinfo>` + per-file `<hash>` records,
  ISO-8601 timestamps, well-formed XML (validates with `xmllint`).
- `VerifiedBackupService`: walks source tree, hash → copy →
  re-hash → compare for each destination, emits one `.mhl` manifest
  per destination on completion. Mismatches fail the file
  individually (others continue).
- BackupView sheet: source + up to 4 destination pickers, hash algo
  segmented control (SHA-1 default per MHL convention), live per-file
  progress with state icons (queued/hashing/copying/verifying/done/
  failed), reveal-in-finder for each written `.mhl`.
- Toolbar action: "Verified Backup" (next to Transcode).

## Unreleased — Sidebar layout: HStack pattern adopted

- Replaced `NavigationSplitView` in `ContentView` with manual `HStack` +
  fixed 240px sidebar (MusicJournal-proven pattern). Rationale:
  `NavigationSplitView` on macOS 14+ does not reliably honor
  `.navigationSplitViewColumnWidth(min:)` at runtime layout — persisted
  state inside the declared range still mis-rendered the sidebar
  narrower than min, even after `.savedState` wipe.
- Added `⌃⌘S` Toggle Sidebar via `@AppStorage("sidebarVisible")`.
- `WindowStateGuard` retained for nested `VSplitView`/`HSplitView`
  inside the detail tree (browser table / player split).
- Documented as canonical PhantomLives pattern in
  `~/Documents/GitHub/PhantomLives/CLAUDE.md` and memory rule
  `feedback_split_view_state_guard`.

## Unreleased — Phase 6: transcode

- Six built-in transcode presets: H.264 1080p/720p, HEVC 1080p,
  ProRes Proxy, ProRes 422, and pass-through rewrap.
- `TranscodeService` wraps `AVAssetExportSession` with progress
  polling, output naming with collision suffix, and codec
  compatibility gating (H.264/HEVC require asset compatibility check;
  ProRes / pass-through always available).
- `TranscodeQueue` (@MainActor): single-worker serial drain — keeps
  the hardware HEVC encoder unsaturated and progress predictable.
- Transcode menu in toolbar (enabled when a clip is selected); queue
  sheet with per-job progress, cancel, and "Reveal in Finder" on
  completion.
- Default output: `~/Downloads/PurpleReel/transcoded/`.

## Unreleased — Phase 5: LUT preview

- Adobe `.cube` LUT parser (3D LUTs native; 1D LUTs synthesized into
  a 33³ cube by per-channel curve sampling).
- LUTs applied in real time via `AVVideoComposition` with a
  `CIColorCubeWithColorSpace` filter; rebuild on LUT change or asset
  load.
- LUT bar under the transport: load `.cube`, show name + cube size,
  clear, persist last-used path via UserDefaults.

## Unreleased — Phase 2: player + logging

- AVPlayer-based detail pane with custom transport (play/pause, 1-frame
  step, J/K/L shuttle rates, I/O markers, click-to-seek scrubber).
- Frame-accurate SMPTE timecode (HH:MM:SS:FF, non-drop) display.
- Marker creation at playhead (M); markers list with inline note
  editing and timecode-jump-to-marker.
- Subclip creation from I/O range (S); subclips list with jump-to-in
  and jump-to-out.
- Tag chips with add (Return) and remove (× click).
- 1–5 star rating + free-form description per asset.
- All detail state persists through GRDB CRUD on `marker`, `subclip`,
  `tag` / `asset_tag`, `rating` tables.

## Unreleased — Phase 1 skeleton

- Scaffolded XcodeGen project, GRDB dependency, asset catalog with
  programmatic film-reel `AppIcon`.
- Catalog schema (assets, tags, markers, subclips, ratings, transcripts,
  FTS5 search table).
- Finder-rooted recursive `MediaScanner` with AVFoundation-derived
  video metadata (codec, resolution, fps, duration).
- Browser view: filterable table of catalog contents.
- Auto-backup-on-launch (zip of `~/Library/Application Support/PurpleReel/`)
  per PhantomLives convention.
- Build/install scripts mirroring `PurpleTracker` conventions.
