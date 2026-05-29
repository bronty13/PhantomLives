# PurpleVoice — Handoff

Snapshot of where the project stands so a future session (human or AI)
can pick up without re-deriving everything from the commit history.
Last updated: 2026-05-28. Initial release session: v0.1.0 → v0.2.0 →
v0.3.0 → v0.4.0 all landed in a single sitting. Test count 60. Bundle is
Developer-ID signed (hardened runtime), notarisation-ready.

## What it is

macOS app + CLI for voice isolation and vocal enhancement on short
audio (and video) clips. SwiftUI front-end, ffmpeg as the core
processing engine, optional DeepFilterNet (`deep-filter` Rust CLI) as a
second engine. Drag-and-drop a noisy voice memo, get a cleaned file in
`~/Downloads/PurpleVoice/`.

```sh
brew install ffmpeg                # required runtime dep
cargo install deep_filter          # optional, for the DeepFilterNet engine
./build-app.sh                     # release → PurpleVoice.app → /Applications + CLI wrapper + relaunch
./run-tests.sh                     # 61 tests via swift-testing
./install.sh --no-cli              # opt out of installing the CLI wrapper
```

Requires macOS 14+, Swift 5.9+. Tests run via Command Line Tools'
bundled `Testing.framework`; the wrapper script handles the rpath
dance (same pattern as PurpleIRC).

## Architecture at a glance

Plain SwiftPM, single executable target. No external Swift dependencies.

- `PurpleVoiceApp` (`@main`) — SwiftUI App. `WindowGroup` with the main
  UI, separate `Settings` scene with three tabs (General, Processing,
  Advanced).
- `AppDelegate` — wired via `@NSApplicationDelegateAdaptor`. Two
  responsibilities:
  - **CLI dispatch** in `applicationWillFinishLaunching` — if argv[1] is
    `clean` / `help` / `version` / `-h` / `--help` / `-v` / `--version`,
    bridge to async CLI flow via `DispatchSemaphore` and `exit(0)`
    before SwiftUI ever materialises a window. This is why a single
    `.app` binary works as both a GUI and a terminal command.
  - **WindowStateGuard** preflight + versioned reset, mirror of the
    PurpleReel pattern.
- `ProcessingQueue` (`@MainActor`) — top-level observable store for the
  sidebar's clip list. `ingest(urls:settings:)` dedupes against existing
  + within-batch sources, kicks off serial processing automatically.
- `ProcessingProfile` / `ProcessingEngine` / `LoudnessTarget` /
  `OutputFormat` — Codable enums backing the various pickers + CLI.
- `SettingsStore` — `@AppStorage` over UserDefaults. The enum/URL
  accessors (`outputDirectory`, `outputFormat`, `profile`,
  `processingEngine`, `loudnessTarget`) and, as of v0.4, the Bool
  toggles + `deepFilterPathOverride` + `activePresetIDRaw` are all
  computed wrappers over a private `@AppStorage` so their setters fire
  `objectWillChange` (bare `@AppStorage` inside an `ObservableObject`
  doesn't publish, so dependent views — e.g. a knob whose enabled-state
  tracks `deEsserEnabled` — wouldn't re-render). `filterTuning` is a
  single JSON blob (`filterTuningJSON`). v0.4 added `apply(_:)`,
  `liveSnapshot`, `matchesLive(_:)` for presets; `effectiveTuning` now
  just returns `filterTuning` (the v0.3 "custom tuning" master gate is
  gone — knobs are always live).
- `Preset` (`Models/Preset.swift`) — Codable bundle of the
  sound-affecting fields (profile, engine, enhancement, loudness, the
  four toggles, `tuning`). NOT output format. `builtIns` is a
  code-defined array with fixed UUIDs (so a persisted `activePresetID`
  survives relaunch/updates); `hasSameSettings(as:)` powers the
  "Modified" check.
- `PresetStore` (`Services/PresetStore.swift`, `ObservableObject`) —
  owns user presets (persisted as one JSON array under
  `userPresetsJSON`), exposes `all` (built-ins + user), and CRUD
  (`add`/`update`/`delete`/`rename`/`duplicate`/`preset(named:)`).
  Injected as an `environmentObject`; the CLI builds its own instance
  against shared `.standard` defaults so `--preset` resolves user
  presets too.
- `Clip` — `ObservableObject` for each queued audio file. Holds source
  URL, status, progress, output URL, error tail, duration, optional
  `trimStart` / `trimEnd` window.
- `FilterChainBuilder` — pure function producing the ffmpeg `-af`
  string from an `Options` struct (profile, enhancement, skip-denoise,
  loudness target, de-esser, de-clicker, tuning overrides). Unit-tested
  end-to-end against every combination.
- `ClipProcessor` (`actor`) — runs the pipeline. Two-stage when
  DeepFilterNet engine is picked (decode → DFN → ffmpeg
  enhancement/encode), single-stage otherwise. Progress is mapped 0–0.5
  / 0.5–1.0 across the two stages so the UI bar tracks honestly. The
  `Process`/`Pipe`/cancellation lifecycle lives in one shared
  `runProcess(executable:args:onStdoutLine:)`; `runFFmpeg` passes the
  `out_time_us=` progress closure, the DFN path passes none and runs a
  synthetic ticker alongside.
- `FFmpegLocator` / `DeepFilterNetLocator` — same search-order pattern
  for both: env var override (`PURPLE_VOICE_FFMPEG`,
  `PURPLE_VOICE_DEEPFILTER`), known paths (Homebrew Apple Silicon +
  Intel, MacPorts, `~/.cargo/bin/` for DFN), then `which` against an
  augmented PATH.
- `AudioPlayer` (`@MainActor`) — thin wrapper around `AVAudioPlayer`.
  Single-stream — starting a new playback stops the previous. `play`,
  `seek` (load branch), and `swap` (paused branch) all route through one
  private `load(url:at:autoplay:)`. Supports swap (used by A/B preview)
  and the DAW-style scrub lifecycle (`beginScrub` / `scrubSeek(to:)` /
  `endScrub`). v0.4: `isMeteringEnabled` + a `meterLevel`/`meterPeak`
  pair published off the 0.05 s ticker (average-power dB → 0…1) drive
  the `LevelMeter`s.
- `WaveformGenerator` / `WaveformCache` — AVAssetReader-based PCM mix
  down + bucket downsample to N min/max pairs (default 1500). Cached
  on disk under `~/Library/Caches/PurpleVoice/waveforms/<sha256>.json`,
  keyed by `path|size|mtime` so in-place edits invalidate the cache.

### View layer

```
ContentView
├── HStack
│   ├── SidebarView         (clip queue; rows with status icons + inline progress)
│   └── mainPane
│       ├── MissingFFmpegView     (when ffmpeg not found at launch)
│       ├── DropZoneView          (no clip selected → drop target + ProcessingPanel)
│       └── ClipDetailView        (clip selected)
│           ├── header
│           ├── statusRow
│           ├── HStack( WaveformView + LevelMeter ×2 "in"/"out" )
│           ├── playbackRow       (A/B picker + play/stop + remove)
│           └── ProcessingPanel   (preset bar + profile + knobs + toggles + pickers)
└── Settings scene (4 tabs: General / Processing / Presets / Advanced)

ProcessingPanel (Views/ProcessingPanel.swift) is the shared console,
rendered by both DropZoneView and ClipDetailView:
  • preset bar — apply menu (built-in + My Presets) + ⋯ menu
    (Save as New… / Update / Revert / Manage Presets…) + Modified badge
  • profile segmented control + blurb
  • a row of rotary Knob (Views/Controls/Knob.swift) — high-pass,
    denoise, de-ess, comp threshold, comp ratio, limiter; each binds to
    a FilterTuning field (nil = inherit profile default), dims when its
    stage is inactive, double-click resets
  • toggle row (enhance / de-esser / de-clicker / stereo / dereverb)
  • engine / loudness / format pickers
LevelMeter (Views/Controls/LevelMeter.swift) — vertical green→red bar
  with peak-hold; the "in"/"out" pair tracks the A/B selection.
ManagePresetsView (Views/ManagePresetsView.swift) — rename/delete/
  duplicate/new; used as the ⋯ → Manage sheet AND the Settings →
  Presets tab (embedded: true).
```

### CLI

`Sources/PurpleVoice/CLI/CLI.swift` lives in the GUI target — the
`@main` AppDelegate dispatches into it before SwiftUI initialises. The
CLI's `clean` subcommand parses argv into a `ProcessingOptions` and
runs the same `ClipProcessor` the GUI uses. Sourced flags mirror the
sheet 1:1 (`--profile`, `--engine`, `--lufs`, `--de-esser`,
`--de-clicker`, `--stereo`, `--dereverb`, `--trim`,
`--highpass-hz`, `--denoise-db`, `--de-esser-intensity`,
`--compressor-threshold-db`, `--compressor-ratio`,
`--limiter-ceiling`). v0.4 adds `--preset <name>` (resolved via
`PresetStore`, applied as the base before the regular flags so any
explicit flag overrides it — handled by a pre-scan + a no-op loop case)
and a `presets` subcommand that lists built-in + user preset names.
`AppDelegate.isCLICommand` includes `presets` in its dispatch table.

Shell wrapper at `/opt/homebrew/bin/purplevoice` (or `/usr/local/bin/`
or `~/.local/bin/` as fallbacks) exec's into the .app binary. Installed
by `install.sh` unless `--no-cli` is passed.

## Version history (in this session)

| Version | What changed | Bumps |
|---------|-------------|-------|
| 0.1.0   | Initial release: drag-and-drop queue, three strength profiles, optional enhancement chain, A/B playback buttons, three output formats, missing-ffmpeg pane, WindowStateGuard, 16 tests | Initial scaffold |
| 0.2.0   | DeepFilterNet engine, loudness normalization (Podcast/Streaming/Broadcast LUFS), de-esser + de-clicker, dereverb (DFN only), preserve-stereo toggle, waveform display, region trim with draggable handles, A/B picker swap, hybrid binary CLI with `purplevoice` wrapper, three-tab Settings, 34 tests | +18 |
| 0.3.0   | Fine-tune sheet with sliders (highpass cutoff, denoise dB, de-esser intensity, compressor threshold + ratio, limiter ceiling); per-slider reset + master toggle; CLI mirrors with `--*` flags; draggable + click-to-seek playhead; DAW-style scrub (audio audible during drag, visual ticker frozen so playhead doesn't lurch toward end), 46 tests | +12 |
| 0.4.0   | Pro-console UI: per-filter rotary knobs + live in/out level meters on the main surface (Tune… sheet + custom-tuning master toggle removed). Presets subsystem: `Preset`/`PresetStore`, 8 built-ins, save/rename/duplicate/delete (Manage sheet + Settings → Presets tab). CLI `--preset` + `presets`. Refactors: `ClipProcessor.runProcess`, `AudioPlayer.load`, `WaveformView` emptyText. SettingsStore Bool toggles → computed-with-objectWillChange. CLI `clean` main-thread deadlock fixed (run loop). USER_MANUAL added. 61 tests | +15 |

## Filter chain rationale

Order of stages, left to right (audio's processing order):

```
highpass → afftdn → anlmdn → lowpass → adeclick → deesser
        → dynaudnorm → acompressor → alimiter → loudnorm
```

- `highpass=f=80` — kill rumble below speech fundamentals. Tunable
  (20–200 Hz).
- `afftdn` — frequency-domain noise reduction (stationary noise:
  AC hum, hiss, fan). `nr` (noise reduction strength) per profile:
  8/12/20 dB (light/medium/aggressive); `nf=-25` fixed; `tn=1` only on
  aggressive (per-frequency tracking). `nr` is tunable.
- `anlmdn` — non-local-means residual denoise. Only on medium /
  aggressive (this is the stage that introduces the "underwater"
  artifact, so light skips it). Not currently tunable — its params are
  too obscure to expose.
- `lowpass=f=12000` — band-limit highs cleanup-up by denoising. Skip
  in light (preserves clarity) and when denoise was upstreamed by DFN.
- `adeclick` — transient click / pop removal. Opt-in via toggle. Runs
  before de-esser so sibilance reduction sees a clean transient
  profile.
- `deesser` — sibilance suppression. Opt-in. Targets ~6.5 kHz by
  default. Intensity tunable (0–1).
- `dynaudnorm=g=5:f=200` — dynamic normalization, evens out clip-to-
  clip level swings.
- `acompressor` — gentle compression. Off in light (preserves
  dynamics). Threshold (-60…0 dB) and ratio (1…20) tunable.
- `alimiter` — brick-wall peak limiter. Ceiling tunable (0.5…1.0
  linear).
- `loudnorm=I=…:TP=-1.5:LRA=11` — single-pass loudness normalization.
  LUFS target per preset (-16 podcast, -14 streaming, -23 broadcast).
  Runs last so it measures the fully-processed signal.

When the DeepFilterNet engine is picked, `skipDenoise: true` is set —
the `afftdn`, `anlmdn`, and `lowpass` stages are omitted (DFN already
denoised and band-limited). Highpass + cleanup + dynamics + loudnorm
still run as normal.

## Key design decisions

### Hybrid CLI/GUI binary

The same `PurpleVoice.app/Contents/MacOS/PurpleVoice` executable
handles both modes. Dispatch happens in
`AppDelegate.applicationWillFinishLaunching` — NOT in `static
main()`. The first attempt was to intercept at a custom `@main`
struct, but that broke SwiftUI's `WindowGroup` registration: SwiftUI
macros require `@main` to stay on the `App` struct itself; intercepting
earlier produced a process that ran but never opened a window.
Dispatching from the AppDelegate works because NSApplication has
already partially initialised by then, and a clean `exit(0)` from the
CLI path tears everything down cleanly.

**Do not block the main thread while the CLI runs.** The CLI is kicked
off in a `Task.detached` and the dispatcher then calls `CFRunLoopRun()`
(NOT a `DispatchSemaphore.wait()`). `ClipProcessor.process` hops to
`@MainActor` to stamp the clip duration, and the GUI progress handler
posts to `DispatchQueue.main`; both are serviced by the main run loop.
A blocked main thread deadlocks the whole `clean` pipeline — that was a
latent bug from v0.3.0 (the bundled `clean` path was never run
end-to-end) fixed in v0.4.0 by switching to `CFRunLoopRun()` +
`CFRunLoopStop(CFRunLoopGetMain())` on completion.

### Sidebar layout: manual HStack

Per CLAUDE.md's "avoid `NavigationSplitView`" rule. PurpleVoice uses
the verbatim `HStack` pattern from PurpleReel/MusicJournal. Fixed
240pt sidebar width, `@AppStorage("sidebarVisible")` toggle via
⌃⌘S. `WindowStateGuard` runs as belt-and-braces even though there's
no top-level NavigationSplitView (covers any future nested
`HSplitView`/`VSplitView`).

### DAW-style scrub (v0.3)

The user reported the scrub feeling rough. First fix tried muting
during scrub — user pushed back: they wanted audible scrub like
Logic/Pro Tools. The actual root cause was visual: a 50ms timer was
updating the playhead from `player.currentTime`, but the AVAudioPlayer
keeps advancing time while playing. Holding a drag still made the
playhead lurch toward the end (timer-driven), then snap back to the
drag position whenever the mouse moved. Fix: freeze the timer for the
duration of the scrub so `scrubSeek(to:)` is the only thing moving
`currentTime`. Audio plays continuously; visual playhead is locked to
the drag.

The scrub still isn't true Logic-style sample-rate-modulated scrub
(would need `AVAudioEngine` + buffer scheduling). What it does is play
forward from the drag position at 1× until the next mouse update snaps
it back. Good enough for QuickTime/Music-style scrubbing.

### DeepFilterNet integration

Not bundled. The Rust binary is ~15 MB and we don't want it in git.
Users install via `cargo install deep_filter` and we auto-detect. If
DFN is selected as the engine and not found, processing throws
`ClipProcessorError.deepFilterNotFound` with a clear install hint —
the Advanced settings tab also shows reachability with a re-check
button.

### Window placement on multi-monitor

**Known caveat carried over from v0.2:** SwiftUI's `WindowGroup`
cascade places the first window on whichever screen was last active,
which on a laptop+external setup may not be the screen the user is
looking at. CGWindowList confirms the window exists; users may need
to look at the other monitor or drag the window across (SwiftUI
persists position after that). Programmatic `setFrame` on the
`SwiftUI.AppKitWindow` subclass is silently ignored, so the obvious
fix doesn't work — proper fix would need a custom NSWindow delegate
or `.defaultPosition` on the WindowGroup. Deferred.

## File layout

```
PurpleVoice/
├── Package.swift
├── build-app.sh                     # build → sign → install → relaunch (one command)
├── install.sh                       # quit-running → replace /Applications/ → install CLI wrapper → relaunch
├── run-tests.sh                     # Testing.framework rpath wrapper
├── README.md
├── USER_MANUAL.md                   # end-user walkthrough (presets, console, CLI, troubleshooting)
├── CHANGELOG.md
├── HANDOFF.md                       # this file
├── Sources/PurpleVoice/
│   ├── App/
│   │   ├── PurpleVoiceApp.swift     # @main App; WindowGroup + Settings scene + commands
│   │   ├── AppDelegate.swift        # CLI dispatch + WindowStateGuard + NSApp activation
│   │   ├── Version.swift            # CFBundleShortVersionString + CFBundleVersion readers
│   │   └── Info.plist               # signed into bundle by build-app.sh
│   ├── CLI/
│   │   └── CLI.swift                # `clean` / `help` / `version` subcommand impl
│   ├── Models/
│   │   ├── Clip.swift               # @ObservableObject per queued clip
│   │   ├── ProcessingProfile.swift  # + OutputFormat enum
│   │   ├── ProcessingEngine.swift   # ffmpeg vs deepFilterNet
│   │   ├── LoudnessTarget.swift     # off / podcast / streaming / broadcast
│   │   ├── FilterTuning.swift       # per-filter knob overrides + Bounds
│   │   ├── Preset.swift             # Codable preset bundle + 8 built-ins (v0.4)
│   │   ├── SettingsStore.swift      # @AppStorage-backed; apply()/liveSnapshot/matchesLive
│   │   └── ProcessingQueue.swift    # @MainActor; ingest + serial drain
│   ├── Services/
│   │   ├── FFmpegLocator.swift
│   │   ├── DeepFilterNetLocator.swift
│   │   ├── FilterChainBuilder.swift # pure -af string builder
│   │   ├── ClipProcessor.swift      # actor; two-stage DFN + ffmpeg pipeline; shared runProcess; ProcessingOptions struct lives here
│   │   ├── AudioPlayer.swift        # AVAudioPlayer wrapper + scrub lifecycle + metering; single load() loader
│   │   ├── PresetStore.swift        # ObservableObject; user-preset CRUD + persistence (v0.4)
│   │   ├── WaveformGenerator.swift  # AVAssetReader → downsampled peaks
│   │   ├── WaveformCache.swift      # on-disk JSON cache keyed by path|size|mtime
│   │   └── WindowStateGuard.swift   # CLAUDE.md convention (verbatim from PurpleReel)
│   └── Views/
│       ├── ContentView.swift        # HStack root
│       ├── SidebarView.swift        # queue rows
│       ├── ClipDetailView.swift     # waveform + level meters + A/B + console + error pane
│       ├── DropZoneView.swift       # drop target + ProcessingPanel (shared)
│       ├── ProcessingPanel.swift    # the console: preset bar + profile + knobs + toggles + pickers (v0.4)
│       ├── ManagePresetsView.swift  # rename/delete/duplicate; sheet + Settings tab (v0.4)
│       ├── WaveformView.swift       # canvas + trim handles + draggable playhead + click-to-seek
│       ├── Controls/
│       │   ├── Knob.swift           # rotary knob bound to Optional<Double> (v0.4)
│       │   └── LevelMeter.swift     # vertical playback meter w/ peak-hold (v0.4)
│       ├── SettingsView.swift       # 4 tabs (General / Processing / Presets / Advanced)
│       └── MissingFFmpegView.swift  # shown when FFmpegLocator returns nil
└── Tests/PurpleVoiceTests/
    ├── FilterChainBuilderTests.swift  # 9 cases: per-profile, enhancement toggle, skipDenoise, loudnorm
    ├── FilterTuningTests.swift        # 9 cases: each override, no-op inherited, JSON round-trip
    ├── LoudnessTargetTests.swift      # 2 cases (inside FilterChainBuilderTests file)
    ├── SettingsStoreTests.swift       # 4 cases: defaults, _clean suffix, collision avoidance, format ext
    ├── FFmpegLocatorTests.swift       # 3 cases: env override, non-exec fallthrough, dev-Mac smoke
    ├── DeepFilterNetLocatorTests.swift # 3 cases
    ├── ClipProcessorTests.swift       # 6 cases: tail(), queue de-dupe, accepted ext, e2e trim duration, e2e stereo
    ├── WaveformGeneratorTests.swift   # 2 cases: bucket count + normalization, cache round-trip
    ├── CLITests.swift                 # 6 cases: parseTrim shapes, isCLICommand table, valueAfter, resolvePreset
    ├── CLITuningFlagTests.swift       # 1 case (inside FilterTuningTests file)
    ├── PresetTests.swift              # 5 cases: built-ins well-formed/unique, JSON round-trip, apply/matchesLive (v0.4)
    ├── PresetStoreTests.swift         # 8 cases: CRUD, ordering, name lookup, persistence (v0.4)
    └── AudioPlayerTests.swift         # 3 cases: seek lifecycle, scrub lifecycle (v0.3 regression), normalize meter mapping
```

## Testing

```sh
./run-tests.sh
```

61 cases across 13 suites. ~1.7s wall time. Tests that depend on
ffmpeg skip gracefully when it isn't installed (return early without
asserting), so the suite still passes on machines without Homebrew
ffmpeg. `PresetStoreTests` use a throwaway `UserDefaults(suiteName:)`
so they never touch real app defaults.

End-to-end tests that actually spawn ffmpeg:
- `Trim window produces a shorter output of the expected duration`
- `preserveStereo controls output channel count`
- `Downsamples a real audio file to the requested bucket count`
- `seek(to:) updates currentTime against a loaded file`
- `Scrub lifecycle keeps audio audible and freezes the visual ticker`

The scrub-lifecycle test is the canonical regression check for the v0.3
"playhead lurches toward end" bug — it explicitly asserts that
`currentTime` does not auto-advance during a held scrub even after a
250ms wait.

## Things deferred / TODO ideas

- **Video re-mux** — video inputs currently produce audio-only output.
  Re-muxing the cleaned audio back into the original container is the
  highest-value missing feature.
- **Multi-monitor first-launch placement** — see "Window placement"
  above. Needs custom NSWindow delegate or `.defaultPosition` work.
- **True Logic-style scrub** — would need `AVAudioEngine` + buffer
  scheduling. Current behaviour is "good enough" QuickTime-style.
- **Per-clip tuning overrides** — tuning is currently global. Could
  add a per-Clip `FilterTuning` that overrides the global. (Presets are
  also global; same lift.)
- **Simultaneous in/out level meters** — the "in"/"out" meters
  currently reflect whichever single stream is audible (the A/B
  selection), since `AudioPlayer` is single-stream. True simultaneous
  metering would need a second `AVAudioPlayer` (or `AVAudioEngine` taps)
  to play/meter original + cleaned at once.
- **Two-pass loudnorm** — current `loudnorm` is single-pass for speed;
  two-pass would be more accurate for podcast publishing.
- **Sparkle auto-update** — not wired. PurpleDedup has the pattern if
  this becomes important.
- **App icon** — `Resources/AppIcon.icns` not yet created. Bundle uses
  the generic Swift icon.

## Per-session Claude permission

The install.sh actions that need allowance in
`.claude/settings.local.json`:

```json
"Bash(rm -rf /Applications/PurpleVoice.app)",
"Bash(ditto --noextattr * /Applications/PurpleVoice.app)",
"Bash(osascript -e 'tell application \"PurpleVoice\" to quit')",
"Bash(open /Applications/PurpleVoice.app)"
```
