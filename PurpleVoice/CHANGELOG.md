# PurpleVoice Changelog

## v0.3.0 — 2026-05-28

Fine-tune adjustments + a draggable, click-to-seek playhead on the waveform.

### Fine-tune sheet

- **Tune… button** on the processing controls opens a sheet with sliders for the per-filter knobs that matter most: high-pass cutoff, denoise depth (`afftdn nr`), de-esser intensity, compressor threshold + ratio, limiter ceiling.
- **Master toggle** — "Apply custom tuning" gates whether overrides are used. Off means everything falls back to the profile defaults; the slider values are still remembered.
- **Per-slider reset** — each override gets an explicit "↺" button that clears just that knob (back to the profile default), so you can override one parameter without losing the rest.
- **Reset all to profile** — one-click full clear in the sheet's footer.
- **Sensible bounds** baked into `FilterTuning.Bounds` so sliders never produce a value ffmpeg would reject (e.g., compressor ratio capped at 20:1, limiter ceiling stays above 0.5).
- **Storage** is a single JSON blob in `UserDefaults` (key `filterTuningJSON`) — adding new tunables in future versions won't require a migration.

### Draggable + click-to-seek playhead

- The red playhead on the waveform is now **always visible** (not just while playing), has a grip-knob at the top for affordance, and a 14pt-wide invisible hitbox so users can grab it without pixel precision.
- **Drag the playhead** to scrub through the clip; the active audio player jumps in real time. Play/pause state is preserved.
- **Click anywhere in the waveform** to seek to that point — even before pressing Play.
- Trim handles sit on top in the Z-order so they still win when they overlap the playhead.
- `AudioPlayer.seek(to:url:)` is the new entry point — preserves play/pause, clamps to `[0, duration)`, and can attach to a URL paused at the requested offset if nothing is loaded yet (so click-to-seek before Play works).

### CLI

- New per-filter flags mirror the sheet: `--highpass-hz`, `--denoise-db`, `--de-esser-intensity`, `--compressor-threshold-db`, `--compressor-ratio`, `--limiter-ceiling`. Each validates against the same bounds the sheet uses; out-of-range values exit non-zero with a clear message.
- `purplevoice clean memo.m4a --denoise-db 18 --limiter-ceiling 0.92` — example.

### Tests

- 45 cases now (up from 34). New: chain composition with every individual tuning override, identity check that empty tuning produces the same chain as the bare profile, `hasAnyOverride` toggle, JSON round-trip, and `AudioPlayer.seek(to:)` against a real WAV with three scenarios (no-load no-op, seek-load with URL, mid-load seek, out-of-bounds clamping).

## v0.2.0 — 2026-05-28

Big engine + UI release. New optional ML denoiser, loudness normalization, sibilance / pop removal, waveform display with region trim, A/B preview, stereo preservation, and a CLI mode.

### New engines & filters

- **DeepFilterNet engine** — optional second engine that runs the `deep-filter` Rust CLI as a first pass (neural denoise) before handing off to ffmpeg for enhancement/loudness/encoding. Pick it under **Settings → Processing → Engine**. Install with `cargo install deep_filter`; PurpleVoice probes `~/.cargo/bin/`, `/opt/homebrew/bin/`, `/usr/local/bin/`, `/opt/local/bin/`, `PATH`, and an explicit override path in Advanced.
- **Loudness normalization** — `loudnorm` filter wired up with three presets: Podcast (-16 LUFS, Apple Podcasts), Streaming (-14 LUFS, Spotify / Apple Music / YouTube), Broadcast (-23 LUFS, EBU R128). Single-pass, runs last so it measures the fully-processed signal.
- **De-esser** — `deesser` filter toggle; targets ~6.5 kHz at moderate intensity. Off by default.
- **De-clicker** — `adeclick` filter toggle for vinyl pops, mic hits, mouth clicks. Off by default. Runs before the de-esser so sibilance reduction sees a clean transient profile.
- **Dereverb** — toggle (DeepFilterNet engine only) that enables DFN's post-filter for stronger residual-reverb suppression. Greyed out when ffmpeg engine is selected (no good ffmpeg-native dereverb exists).
- **Preserve stereo** — opt-out from the default mono downmix. For music podcasts, stereo field recordings, or anything where ambient panning matters.

### New UI

- **Waveform display** — original (top) and cleaned (bottom) stacked waveforms in the detail pane, with a live playhead overlay while audio plays. Drawn from a downsampled 1500-bucket min/max pair; cached under `~/Library/Caches/PurpleVoice/waveforms/` so repeat opens are instant.
- **Region trim** — drag the two handles on the waveform to set a start/end. Only the trimmed slice gets processed (saves time on long inputs, especially with DeepFilterNet). Both ffmpeg-only and DFN pipelines honor the trim; trim window is applied before DFN so we don't denoise the bits we're throwing away. "Clear Trim" button resets.
- **A/B preview** — segmented picker above the player swaps between **Original** and **Cleaned** sources without restarting playback. Position and play/pause state are preserved across the swap. Spacebar toggles play.
- **Settings has three tabs** — General, Processing (engine + loudness + cleanup + channels), Advanced (DeepFilterNet / ffmpeg path overrides + reachability checks).

### CLI

- **Hybrid binary** — the same `.app` executable handles both GUI (no args, launched from Finder) and CLI (with `clean` / `help` / `version` subcommands) modes. Dispatch happens in `MainEntry.swift` before SwiftUI initializes.
- **`purplevoice` command** — `install.sh` now drops a thin shell wrapper into the first writable PATH entry (`/opt/homebrew/bin/`, `/usr/local/bin/`, or `~/.local/bin/` as a no-sudo fallback). Opt out with `./install.sh --no-cli`.
- **Full feature surface** — every GUI option has a flag: `purplevoice clean foo.m4a -o cleaned.wav -p aggressive --engine deepfilter --lufs podcast --de-esser --de-clicker --stereo --trim 1.5:30.0 -f wav`. `purplevoice help` for the full list.

### Tests

- 34 Swift Testing cases (up from 16). New coverage: loudness chain composition, de-esser/de-clicker toggles and ordering, `skipDenoise` path used by DFN, DeepFilterNet locator search order + overrides, end-to-end ffmpeg trim duration, end-to-end stereo channel-count round-trip, waveform generator output shape + normalization, waveform cache round-trip, CLI `--trim` parser, CLI dispatch routing.

### Internal

- `ProcessingOptions` struct bundles everything the processor needs — call sites (queue, CLI) no longer thread a dozen positional args.
- `ClipProcessor` is now a two-stage coordinator: decode → DeepFilterNet → ffmpeg (when DFN engine selected) vs. single-pass ffmpeg (otherwise). Progress is mapped 0–0.5 / 0.5–1.0 across the two stages so the UI bar tracks honestly.
- `FilterChainBuilder.chain(options:)` replaces the old positional form (still available as a back-compat shim).

## v0.1.0 — 2026-05-28

Initial release. Voice isolation + enhancement for audio and video clips on macOS.

- Drag-and-drop queue, three strength profiles (Light/Medium/Aggressive), optional enhancement chain.
- Side-by-side playback (original vs. cleaned), three output formats (M4A/MP3/WAV).
- Input formats: m4a, aac, mp3, wav, aif/aiff, caf, mp4, m4v, mov.
- Default output `~/Downloads/PurpleVoice/<stem>_clean.<ext>`.
- Missing-ffmpeg pane with install hint + re-check.
- WindowStateGuard wired up per the PhantomLives convention.
- 16 Swift Testing cases.
- Standard `build-app.sh` → `install.sh` chain, Developer ID signing.
