# PurpleReel

A FCP-only, AI-augmented alternative to Kyno. Native macOS, all
processing local, no telemetry.

Built on the PhantomLives stack: SwiftUI + GRDB + XcodeGen, integrated
with the sibling `transcribe/` MLX-Whisper project and local Ollama.

## Why PurpleReel (vs Kyno)

Four reasons doc shooters, post houses, and AE workflows are
migrating off Kyno onto PurpleReel:

- **Apple Silicon native by design.** Pure Swift + SwiftUI built
  against Apple's modern AV stack. Kyno's auto-updater still ships
  the Intel build on Apple Silicon machines as of late 2025 — the
  Rosetta cost shows up in every preview scrub. PurpleReel has no
  Intel build to confuse the updater with.
- **Active development, public roadmap.** Kyno's post-Signiant
  cadence has been slow enough that users openly worry about
  abandonment. PurpleReel ships a monthly changelog (see
  [CHANGELOG.md](CHANGELOG.md) — currently at commit C27) and
  publishes its parity roadmap as [KYNO_PARITY_ROADMAP.md](KYNO_PARITY_ROADMAP.md).
- **Pay-once licensing, not annual-renewal-for-updates.**
  Kyno's model is €159/year and updates stop when the renewal
  lapses. PurpleReel ships from PhantomLives — the licensing
  model is one-time-pay, every update included, runs on every
  Mac you own.
- **Community lives somewhere.** The original Kyno forums were
  taken offline; community questions go unanswered. PurpleReel
  uses GitHub Discussions on the [bronty13/PhantomLives](https://github.com/bronty13/PhantomLives)
  repo — every issue, every feature request, every release note
  is in one place, searchable, permanent.

**Migrating?** See
[`MIGRATING_FROM_KYNO.md`](MIGRATING_FROM_KYNO.md) for a step-by-
step walkthrough: setting up your workspace, importing your
existing Kyno metadata via `.LP_Store/` sidecars, round-tripping
with Final Cut via FCPXML, the daily DIT camera-card workflow,
and the Kyno → PurpleReel keyboard-shortcut mapping.

## Features

- **Browser** — Finder-rooted recursive scan with hover-scrub thumbnails
  in the asset table.
- **Player** — AVKit + custom transport with frame-accurate scrubbing,
  audio waveform overlay, multi-rate J/K/L shuttle (¼× → 4× each way),
  I/O markers, real-time `.cube` LUT preview via `AVVideoComposition`.
- **Logging** — markers (M), subclips (S after I/O), tags, 1–5 star
  ratings, free-text descriptions. All persisted in GRDB with FTS5.
- **Transcode** — 9 presets: H.264 1080/720p, HEVC 1080p, ProRes
  Proxy / 422, pass-through rewrap (all native AVAssetExportSession);
  DNxHR SQ / HQ, Cineform, ProRes-in-MXF (ffmpeg).
- **Verified backup** — streaming SHA-1/MD5/SHA-256 to 1–4 destinations
  in parallel, emits ASC Media Hash List v1.1 manifests.
- **FCPXML export** — v1.10 with NTSC-correct frame rates, markers,
  subclips, tags as keywords, 4–5 star clips as Favorite. Auto-launches
  Final Cut Pro.
- **SFTP delivery** — system `sftp -b` with per-file streaming progress;
  SSH key auth or Keychain-backed password auth via `sshpass`.
- **AI augmentation** (all on-device, no internet):
  - **Whisper transcription** → transcript table + auto-markers per
    segment via sibling `transcribe/` MLX pipeline.
  - **Ollama auto-description** → fills the description field from
    filename + transcript snippet via `localhost:11434`.
  - **Similar takes** → middle-frame dHash + BK-tree cluster with
    rating/duration ranker.
- **Batch rename** — token template (`{orig}`, `{date[:fmt]}`,
  `{counter[:N]}`, `{codec}`, `{fps}`, `{w}`, `{h}`, `{size_mb}`,
  `{ext}`) with live preview + conflict flagging.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16
- `xcodegen` (`brew install xcodegen`)

Optional (each unlocks the feature it gates):

| Tool | Where to get | What for |
|---|---|---|
| Python 3.10+ + sibling `transcribe/` | bundled in PhantomLives | Whisper transcription |
| Ollama | <https://ollama.com> + `ollama pull llama3.2:1b` | Auto-describe |
| ffmpeg | `brew install ffmpeg` | DNxHR / Cineform / MXF presets |
| sshpass | `brew install hudochenkov/sshpass/sshpass` | SFTP password auth |

## Build & install

```sh
./build-app.sh && ./install.sh
```

`build-app.sh` regenerates the AppIcon, runs xcodegen, compiles Release,
signs (Developer ID if available, ad-hoc otherwise). `install.sh`
quits any running copy and ditto-copies into `/Applications/` so TCC
permissions stick across rebuilds.

## Test

```sh
./run-tests.sh
```

28 unit tests across hashing (FIPS vectors), MHL/FCPXML writers
(well-formedness + escape), Whisper SRT parser, batch-rename token
expansion, BK-tree clustering, window-state guard. ~2s wall time.

## Docs

- **[`USER_MANUAL.md`](USER_MANUAL.md)** — full feature reference
  (install, keyboard, toolbar, AI prereqs, output paths, recovery).
- **[`HANDOFF.md`](HANDOFF.md)** — architecture snapshot for new
  working sessions. Read first.
- **[`INTEGRATION_TEST_PLAN.md`](INTEGRATION_TEST_PLAN.md)** —
  end-to-end test scenarios for real-world validation.
- **[`CHANGELOG.md`](CHANGELOG.md)** — what shipped in each round.

## Layout

```
Scripts/generate-icon.swift     # programmatic film-reel app icon
Sources/PurpleReel/
  App/                          # @main, AppState, AppDelegate, Info.plist, entitlements
  Models/                       # Asset, Marker, Subclip, Tag, Rating, BackupJob, ...
  Services/                     # DatabaseService, MediaScanner, BackupService,
                                # WindowStateGuard, LUTService, WaveformService,
                                # ThumbnailService, TranscodeService, TranscodeQueue,
                                # HashingService, MHLWriter, VerifiedBackupService,
                                # FCPXMLWriter, SFTPService, KeychainService,
                                # WhisperService, OllamaService, SimilarTakesService,
                                # BKTree, BatchRenameService, Timecode
  Views/                        # ContentView, BrowserView, PlayerView,
                                # MarkersListView, SubclipsListView, TagsRatingView,
                                # TranscodeQueueView, BackupView, SFTPDeliveryView,
                                # AISheetView, BatchRenameView, SettingsView,
                                # ThumbnailCell
  Resources/Assets.xcassets/    # AppIcon + AccentColor
Tests/PurpleReelTests/          # XCTest, 28 cases
project.yml                     # XcodeGen
build-app.sh / install.sh / run-tests.sh
```

44 Swift files. ~6.4k source LOC. ~540 test LOC.
