# PurpleReel Changelog

PurpleReel uses a build-number-as-version scheme — every commit
bumps the bundle version (`0.1.<git-commit-count>`) via
`build-app.sh`. There are no tagged releases yet, so each section
below is a "milestone" rather than a version. The current build
number is stamped into the app at `About → Version`.

Newest first.

---

## Sprint 8 — Hover-scrub polish (more frames + SMPTE TC tooltip)

Hover-scrub thumbnails (Kyno-parity row 67) were already shipped in
both List view (`ThumbnailCell`) and Grid view (`GridCell`). This pass
polishes them.

- **Strip granularity 12 → 20 frames.** `ThumbnailService.defaultFrameCount`
  bumped so scrubbing a long clip is noticeably finer. Cache key encodes
  the count, so old 12-frame strips stay on disk as orphans and the
  next hover regenerates a 20-frame strip. `ClipDetailInline.GridCell`
  switched from a hard-coded `count: 12` to the default so all hover
  surfaces share the same granularity.
- **SMPTE timecode tooltip during hover.** Both cells now show the
  clip-time at the cursor position (e.g. `00:01:23:15`) as a small
  monospaced overlay near the top of the cell. Uses
  `Timecode.format(seconds: dur * frac, fps: ...)` with the asset's
  duration + frame rate (defaults fps to 30 when missing).
- **Tick-row cleanup.** `ThumbnailCell` previously inferred the active
  frame index by round-tripping `loadedImage.tiffRepresentation`
  against every URL in the strip (O(N) heavy comparison per render).
  Replaced with a state-tracked `activeIdx` mutated in `loadFrame(at:)`.

---

## Sprint 7 — Dark mode (Settings → Appearance)

User-facing appearance picker in Settings → General → Appearance:
**Match System / Light / Dark** (segmented Picker). The pick lives
in UserDefaults under the `appearance` key.

Applied on two layers so the entire window stays consistent —
SwiftUI's `.preferredColorScheme(...)` only retints SwiftUI surfaces;
title bars, NSOpenPanel, NSSavePanel, NSAlert, and any AppKit chrome
keep following `NSApp.appearance`.

- **SwiftUI**: `.preferredColorScheme(preferredColorScheme)` applied
  to the WindowGroup root AND the Settings scene root. The shared
  helper maps `"light" → .light`, `"dark" → .dark`, `"system" → nil`.
- **AppKit**: `AppDelegate.applyAppearance()` mirrors the same pick
  onto `NSApp.appearance` (`.aqua` / `.darkAqua` / `nil`). Observes
  `UserDefaults.didChangeNotification` and re-applies on every flip,
  gated on a value-changed check so unrelated defaults writes don't
  thrash the appearance.

USER_MANUAL: documented under Settings → General → Appearance.

---

## Sprint 6 — Sprint 2 verification + zero-based TC honesty

Sweep of the 15 items in `KYNO_RESEARCH.md`'s Sprint-2 ("Migration
safety net + standalone Smalls") block. Reconnaissance confirmed
all 15 are already wired in trunk:

- Find Lost Metadata, Paste Metadata, Play-All-Selected, Incremental
  transcoding (`AppState.confirmConvert` skip-existing check), shift-
  click hard refresh (`ContentView.swift` modifier detect), smart
  proxy auto-scale presets, Date Recorded/Created columns, Display
  size + Aspect ratio columns, LUT-on-frame-export default, audio
  channel names field, subclip name-collision auto-disambiguate,
  file-count safety-limit warning, transcoder file-timestamp
  preservation, fade in/out.

Only honesty gap was the Settings → Advanced → "Use zero-based
timecode" toggle, which read its UserDefaults key into `_`
(literally discarded the result) in `Timecode.format(seconds:fps:)`.
Today every clip already starts at 00:00:00:00 because the formatter
gets seconds-from-start as input — so the toggle had no observable
effect. Surprises users who flip it expecting a behavior change.

- **Timecode.swift**: removed the dead `_ = UserDefaults...` placeholder
  read; trimmed the surrounding comment to clarify that
  `useZeroBasedTimecode` is reserved for a future container-TC build.
- **SettingsView (Advanced → Timecode)**: added a caption under the
  toggle telling users it's reserved for container-embedded source TC
  surfacing, so they don't think it's broken.

---

## Sprint 5 — Coming-from-Kyno polish

Verification + final polish on the Kyno compatibility bundle that
shipped across Sprints 1-4. Confirmed all 12 keyboard / sort / label
items in `KYNO_RESEARCH.md`'s "Recommended starting sprint" are now
wired end-to-end (preset, first-launch sheet, Settings toggle, menu
bindings, shortcuts catalogue).

- **Detail-view clip stepper visible affordance.** `ClipDetailInline`
  header now shows ◀ / ▶ chevron buttons next to the filename,
  disabled at the ends of the displayed list. The ⌘← / ⌘→ keybindings
  remained as before (wired in `PurpleReelApp.swift`'s View menu) — the
  chevrons just make the feature discoverable for users who didn't
  read the Kyno-compat sheet.
- **Shortcuts catalogue + cheat-sheet.** Added the previously-missing
  ⌘← / ⌘→ "Previous / Next clip" entries to `Help/Shortcuts.swift`
  under the Browser group; cheat-sheet and `SHORTCUTS.md` now show
  them.
- **First-launch sheet copy.** `ComingFromKynoSheet`'s "regardless of
  your choice" paragraph now lists ⌘← / ⌘→ alongside the rest of the
  Kyno-familiar bindings.

---

## Sprint 3-4 — Kyno parity closeout (Medium + Large rows)

A run through every remaining Kyno parity item in `KYNO_RESEARCH.md`.
Builds 327 → 348. Canonical status: `KYNO_RESEARCH.md` (per-row), this
section is the user-facing rollup.

### Medium bucket (rows 10, 11, 14, 15, 18, 27, 28, 41, 47, 52, 61,
68, 80)

- **Timecode burn-in during transcode** (row 10). Convert dialog →
  "Burn timecode into video". `TranscodeJob.applyComposition` switches
  to a CIFilter-handler videoComposition that runs the opacity ramp +
  per-frame TC overlay in one pass.
- **LUT auto-detection** (row 11). `LUTLibraryService` walks PurpleReel
  + FCP `*.fcpbundle` + Resolve LUT roots; `PlayerController.load`
  matches filename keywords (`SLog3` / `V-Log` / `LogC` / `HLG` etc.)
  and auto-applies. Settings → General → "Auto-apply suggested LUT".
- **Folder-tree metadata transfer** (row 14). File → "Transfer Metadata
  Between Folders…" copies clip_metadata + rating + tags across two
  folders matched by filename + size.
- **Batch export frames at every marker, with LUT baked in** (row 15).
  Playback → "Export Frames at Markers…" (⌥⌘⇧E). One PNG per marker,
  filename embeds `HHMMSS_FFf_<note-slug>`.
- **Excel/CSV report with thumbnails** (row 16). File → Export Report
  → CSV / HTML. HTML embeds the middle-frame thumbnail per row as
  base64 PNG; CSV writes 22 columns with RFC 4180 escaping.
- **Paste & rename** (row 18). File → "Paste with Rename…" (⌘⇧V) reads
  file URLs from NSPasteboard, applies a `{date}_{orig}{ext}` template,
  copies into a chosen folder.
- **AND / OR filter combine mode** (row 27). `filterMatchMode` AppStorage
  flips active-filter set between AND and OR. Pills bar exposes the
  chip.
- **VFR vs CFR filter** (row 28). v5 schema adds `asset.isVFR`.
  MediaScanner detects via `nominalFrameRate` vs `minFrameDuration`
  (>10% gap = VFR). Filter → Frame Rate → CFR / VFR / Unknown.
- **Poster-frame keyboard P** (row 41). v6 schema adds
  `asset.posterFrameSeconds`. P key captures the playhead; ⇧P clears.
  `ThumbnailService.posterFrame(for:seconds:)` caches one frame per
  (path, modtime, seconds). Grid + List cells render the poster as the
  at-rest frame; hover-scrub still uses the 12-frame strip.
- **Edit Tags ⌘⇧T + autocomplete** (rows 25, 47). `BatchTagEditorSheet`
  shows union-of-selection tags with "partial" badges, autocomplete
  from known tag names, additive add / batch remove.
- **Pitch-preserved playback at 0.5/0.75/1.25/1.5/2×** (row 52).
  `item.audioTimePitchAlgorithm = .spectral`. Playback → Speed
  sub-menu.
- **C4 IDs + ASC-MHL v2.0** (row 61). `HashAlgorithm.c4` = SHA-512
  base58-with-c4-prefix. New `ASCMHLWriter` emits the Netflix-required
  v2.0 schema. `BackupJob.mhlFormat` picks legacy vs ASC-MHL.
- **Live waveform column in the list view** (row 68). Optional
  `ListColumn.waveform`. `WaveformService.cachedOrGenerate` caches
  peaks as JSON keyed by (path, modtime, bucketCount).
- **Kyno `.LP_Store/` XML import** (row 80). Metadata → "Import from
  Kyno (.LP_Store)…" recursively walks the chosen root and parses
  sidecar XMLs with a permissive XMLParserDelegate (accepts
  schema-drift synonyms — `<asset>`/`<clip>`/`<file>`,
  `<rating>`/`<stars>`, `<tag>`/`<keyword>`).

### Large bucket (rows 5, 7, 8, 29, 57, 66)

- **FCPXML re-import / round-trip** (row 5). Metadata → "Import
  FCPXML…". `FCPXMLImportService.importXML(at:db:)` parses 1.8-1.11
  with a permissive XMLParserDelegate. Match strategy: full URL-decoded
  path → filename fallback. Merge is additive — markers de-duped by
  ±1/fps + note, keywords union as tags, FCP `favorite` raises rating
  to 5★ but never demotes, `<metadata><md/>` fills empty log fields
  only.
- **Combine multiple clips** (row 8). Convert → "Combine Clips…" (⌘⇧J).
  `CombineClipsJob.run()` builds an `AVMutableComposition`, inserts
  video + audio at a running CMTime cursor, copies the first clip's
  `preferredTransform` + `naturalSize` so portrait phone footage stays
  upright, exports via AVAssetExportSession.
- **Shared workspace cache for NAS / SAN** (row 7). Off by default.
  Settings → General → "Write shared metadata cache next to media".
  `<dir>/.purplereel/<filename>.json` per clip carries technical + user
  metadata. MediaScanner's read path checks `loadIfFresh(for:)` first
  and skips AVAsset probes on hit. After scan, `hydrateUserMetadataFromCache`
  runs the user portion through additive merge.
- **Spanned-clip detection** (row 29). `SpanDetectionService.detect(in:)`
  pure-Swift heuristic: same-dir + same-ext + matching tech specs +
  sequential trailing digits (MVI_0001/MVI_0002, C0001/C0002,
  00000/00001) + modtime within 120s. New "Spanned Clips" sidebar
  section; right-click → "Combine Segments…" opens the row-8 sheet
  pre-populated.
- **Centralized cross-volume offline search** (row 57). v7 schema adds
  `asset.volumeUUID` (indexed) + `asset.volumeLabel`. Catalogue persists
  across unmounts; cells fade-overlay + cloud-slash badge offline
  assets. Filter → "Volume / Online status" → Online / Offline.
  `VolumeWatcher.handleMounted` calls `AppState.reconnectVolume(...)`
  to re-anchor paths after a remount renames the volume.
- **Workflow chains** (row 66). `WorkflowChain` model + `WorkflowChainsStore`
  (JSON in UserDefaults). Three step kinds: Verified Backup, Transcode,
  Export Report. `WorkflowChainRun` drives sequential execution with
  per-step state. File → "Workflow Chains…" (⌘⇧Y) does CRUD + run.
  `runOnCameraMediaMount` flag auto-offers the chain when a camera
  card mounts.

### Polish & UX

- **Detail-view tabbed right pane** (Kyno-style). Segmented control
  toggles Metadata / Content / Subclips / Tracks. New `ClipFramesGrid`
  extracted from `ClipContentView`'s frames block. Active tab sticky
  via `clipDetailInspectorTab` AppStorage.
- **Sidebar snap-back from Detail to List**. Clicking a sidebar folder
  while in single-clip Detail used to leave the previous clip stuck
  on screen. `AppState.navigate(to:)` flips `viewMode` to "list" so
  the user lands somewhere browse-able.
- **Right-click menu wired to shipped features**. Five items used to
  fire an "On the Kyno-parity roadmap" alert despite the underlying
  features shipping — Export Markers as Stills, Import Metadata,
  Tags, Edit Multiple, Export Markers as Stills (in Edit menu).
  All now invoke the real methods. Dropped dead-end items (Batch
  Image Transform, per-clip LUT picker).
- **App version**: bumped through builds 327→356 during this run.

---

## Kyno-parity Round 2 — Workspace + history + full menu bar

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

## Kyno-parity round 1 (Content/Tracks tabs, folder tree, browser controls)

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

## Round 2 follow-ups (thumbnails, SFTP pwd, BK-tree)

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

## Post-MVP follow-ups

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

## Phase 11-12: polish + docs

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

## Phase 9-10: AI augmentation

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

## Phase 8: SFTP delivery

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

## Phase 8: FCPXML export

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

## Phase 7: verified backup + MHL

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

## Sidebar layout: HStack pattern adopted

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

## Phase 6: transcode

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

## Phase 5: LUT preview

- Adobe `.cube` LUT parser (3D LUTs native; 1D LUTs synthesized into
  a 33³ cube by per-channel curve sampling).
- LUTs applied in real time via `AVVideoComposition` with a
  `CIColorCubeWithColorSpace` filter; rebuild on LUT change or asset
  load.
- LUT bar under the transport: load `.cube`, show name + cube size,
  clear, persist last-used path via UserDefaults.

## Phase 2: player + logging

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

## Phase 1 skeleton

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
