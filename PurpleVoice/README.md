# PurpleVoice

Voice isolation, vocal enhancement, and loudness normalization for short audio (and video) clips on macOS. Drag a noisy voice memo in, get a clean version back — no plug-ins, no DAW, no signup.

PurpleVoice is a thin SwiftUI front-end over `ffmpeg` and (optionally) DeepFilterNet. There is no cloud round-trip, no telemetry — everything happens locally on your Mac.

## What it does

- **Voice isolation** — two engines:
  - **ffmpeg** (default, always available) — frequency-domain denoise (`afftdn`) + non-local-means residual cleanup (`anlmdn`). Fast, no extra install.
  - **DeepFilterNet** (optional, best quality) — neural speech enhancement that's noticeably ahead of ffmpeg on real-world voice noise. Install with `cargo install deep_filter`.
- **Vocal enhancement** — high-pass to remove rumble, dynamic normalization to even out levels, light compression, brick-wall limiter. Toggle off for pure denoise.
- **Cleanup toggles** — de-esser (sibilance reduction), de-clicker (mouth clicks / mic pops / vinyl crackle), dereverb (DeepFilterNet engine only).
- **Loudness normalization** — `loudnorm` to broadcast standards: Podcast (-16 LUFS), Streaming (-14 LUFS), Broadcast (-23 LUFS).
- **Region trim** — drag handles on the waveform to clean just a portion of the clip. The trim window is applied *before* the denoise so long-form recordings don't waste time on bits you're going to throw away.
- **A/B preview** — flip between original and cleaned mid-playback without losing your position.
- **Scrubbable playhead** — drag the red playhead, or click anywhere in the waveform, to seek. Works before pressing Play.
- **Fine-tune sliders** — "Tune…" button opens a sheet with sliders for the per-filter knobs (high-pass cutoff, denoise depth, de-esser intensity, compressor threshold + ratio, limiter ceiling). Overrides apply on top of your profile; per-slider reset and "reset all" affordances make it easy to back out.
- **Three strength profiles** — Light, Medium (default), Aggressive — tune how hard the denoise hits.
- **Batch queue** — drop a folder, watch it clean one clip at a time.
- **Stereo / mono** — defaults to mono downmix (right for voice work); toggle Preserve Stereo for music podcasts or stereo field recordings.
- **Video inputs** — `.mov`, `.mp4`, `.m4v` accepted; cleaned audio is emitted as a standalone audio file.

## Install

```sh
brew install ffmpeg        # required runtime dependency
cargo install deep_filter  # optional, for the DeepFilterNet engine
./build-app.sh             # builds, signs, installs to /Applications/, drops a `purplevoice` CLI wrapper on PATH, relaunches
```

Don't have `cargo`? `brew install rust`.

`build-app.sh` is the canonical entry point — it auto-chains into `install.sh`. Opt-outs:

```sh
./build-app.sh --no-open      # install without focus-stealing relaunch
./build-app.sh --no-install   # build the bundle, leave /Applications/ alone
./install.sh --no-cli         # don't install the CLI wrapper
BUILD_ONLY=1 ./build-app.sh   # same as --no-install via env (for CI)
./install.sh                   # re-install the last-built bundle (default: with CLI)
```

The app refuses to do anything useful without ffmpeg. If the main pane shows "ffmpeg not found", install via Homebrew and click **Re-check**. DeepFilterNet is optional — only required when you've explicitly picked the DFN engine.

## Use (GUI)

1. Launch PurpleVoice.
2. Drop one or more audio/video clips onto the main pane (or **File → Add Clips…** / ⌘O).
3. Each clip enters the sidebar queue and starts cleaning automatically.
4. When a clip finishes, click it in the sidebar to see the waveform, drag the trim handles to clean just a region, A/B-preview the result, or hit **Reveal in Finder**.

Cleaned files default to `~/Downloads/PurpleVoice/<stem>_clean.<ext>`. Override the output folder, format, engine, loudness target, and other defaults in **PurpleVoice → Settings…** (three tabs: General, Processing, Advanced).

### Picking a profile

| Profile     | When to use                                              |
|-------------|----------------------------------------------------------|
| Light       | A recording that's already mostly clean — gentle de-hiss without dynamics processing |
| Medium      | The default. Voice memo from an iPhone in a normal room. |
| Aggressive  | A loud, noisy recording — café, car, field recording. Watch for "underwater" artifacts. |

If aggressive sounds artificial, drop back to medium. If medium leaves too much noise, try the DeepFilterNet engine before going aggressive — it usually beats ffmpeg-aggressive without the artifacts.

### Picking a loudness target

| Target     | LUFS  | When to use                                  |
|------------|-------|----------------------------------------------|
| Off        | —     | You'll loudness-normalize downstream         |
| Podcast    | -16   | Apple Podcasts standard                      |
| Streaming  | -14   | Spotify / Apple Music / YouTube standard     |
| Broadcast  | -23   | EBU R128 broadcast spec                      |

## Use (CLI)

```sh
purplevoice clean memo.m4a
purplevoice clean talk.mp4 -o talk_clean.wav -p aggressive --lufs podcast
purplevoice clean interview.wav --engine deepfilter --dereverb --stereo
purplevoice clean podcast.m4a --trim 5.0:1800.0 --lufs podcast --de-esser
purplevoice clean memo.m4a --denoise-db 18 --limiter-ceiling 0.92  # fine-tuning
purplevoice help
```

Every GUI option has a flag. `purplevoice help` prints the full list. The CLI binary lands at the first writable PATH directory (`/opt/homebrew/bin/`, `/usr/local/bin/`, or `~/.local/bin/`) when you run `install.sh`; skip with `./install.sh --no-cli`.

## Supported formats

Input: `m4a`, `aac`, `mp3`, `wav`, `aif`/`aiff`, `caf`, `mp4`, `m4v`, `mov`

Output: `m4a` (AAC 192k, default), `mp3` (libmp3lame VBR ~q2), `wav` (PCM 16-bit)

Voice resamples to 48 kHz, mono by default (toggle in Settings → Processing → Channels to preserve stereo). Resolution exposes via `-f` flag in the CLI.

## Tests

```sh
./run-tests.sh
```

Runs the Swift Testing suite (34 tests covering filter chain composition with every toggle combination, loudness target wiring, ffmpeg + DeepFilterNet locator search order, settings round-trip, queue de-duplication, CLI argument parsing, waveform generator + cache, and end-to-end trim/stereo regressions). The wrapper adds `Testing.framework` paths for Command Line Tools setups; with full Xcode installed, plain `swift test` works.

## How the filter chain works

For the curious — the exact `-af` chain PurpleVoice hands ffmpeg for the **Medium profile, enhancement on, podcast LUFS, de-esser on**:

```
highpass=f=80,afftdn=nr=12:nf=-25,anlmdn=s=7:p=0.002:r=0.006,lowpass=f=12000,deesser=i=0.4:m=0.5:f=0.5,dynaudnorm=g=5:f=200,acompressor=threshold=-22dB:ratio=3:attack=5:release=80,alimiter=limit=0.97,loudnorm=I=-16.0:TP=-1.5:LRA=11
```

When the **DeepFilterNet engine** is picked, the source is first decoded to a 48 kHz PCM WAV (honoring the trim window), then handed to `deep-filter`. Its denoised output replaces `afftdn` + `anlmdn` in the ffmpeg chain (`skipDenoise: true`), and the rest of the enhancement / loudness / encoder stages run as normal.

See `Sources/PurpleVoice/Services/FilterChainBuilder.swift` for the per-profile breakdown and `Sources/PurpleVoice/Services/ClipProcessor.swift` for the two-stage coordination.

## What it doesn't do (yet)

- No video re-muxing — video inputs produce audio-only output.
- No vocal extraction from music (use Demucs / Spleeter for that — different problem class).
- No real-time microphone cleanup (use macOS's built-in Voice Isolation, or Krisp).
- No Sparkle auto-update — pull and rebuild.

## License

Personal use within the PhantomLives monorepo.
