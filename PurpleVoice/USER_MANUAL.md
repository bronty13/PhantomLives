# PurpleVoice — User Manual

PurpleVoice cleans up voice recordings: it strips background noise and
enhances the voice so a phone memo, an interview, or a noisy field
recording comes out clear. It's a macOS app with a matching command-line
tool — the same engine drives both.

This manual covers everything you can do. For a quick overview see
`README.md`; for the internal architecture see `HANDOFF.md`.

---

## Contents

1. [Requirements & install](#1-requirements--install)
2. [The 30-second workflow](#2-the-30-second-workflow)
3. [The processing console](#3-the-processing-console)
4. [Presets](#4-presets)
5. [Profiles, engines & loudness](#5-profiles-engines--loudness)
6. [The knobs, one by one](#6-the-knobs-one-by-one)
7. [Waveform, trimming & A/B preview](#7-waveform-trimming--ab-preview)
8. [Settings](#8-settings)
9. [Command line](#9-command-line)
10. [Where files go](#10-where-files-go)
11. [Supported formats](#11-supported-formats)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Requirements & install

- **macOS 14 or later.**
- **ffmpeg** — the required engine. Install with `brew install ffmpeg`.
- **DeepFilterNet** (optional, for the best-quality neural engine) —
  `cargo install deep_filter` (needs Rust: `brew install rust`).

Build and install the app:

```sh
./build-app.sh
```

That builds the app, installs it to `/Applications/PurpleVoice.app`,
drops a `purplevoice` command-line wrapper on your `PATH`, and launches
it. Don't want the CLI wrapper? `./install.sh --no-cli`.

The app needs ffmpeg to do anything. If the main window shows
**"ffmpeg not found,"** install it with Homebrew and click **Re-check**.
DeepFilterNet is only needed if you specifically choose the
DeepFilterNet engine.

---

## 2. The 30-second workflow

1. Launch PurpleVoice.
2. **Drag one or more audio/video files** onto the window — or use
   **File → Add Clips…** (⌘O).
3. Each file lands in the left sidebar queue and starts cleaning
   automatically, one at a time.
4. Click a finished clip to see its waveform, compare **Original**
   vs **Cleaned** with the A/B switch, and **Reveal in Finder**.

Cleaned files are written to `~/Downloads/PurpleVoice/` as
`<name>_clean.<ext>`. That's it — the defaults are tuned for a typical
voice memo. Everything below is for when you want more control.

---

## 3. The processing console

The console is the panel of controls below the drop area (and below the
waveform when a clip is selected). It's shared between both views, so
whatever you set here applies to the next clip you process. Top to
bottom:

- **Preset bar** — pick, save, and manage presets (see §4).
- **Profile** — Light / Medium / Aggressive denoise strength (§5).
- **Knobs** — the per-filter parameters as rotary dials (§6).
- **Toggles** — Enhance, De-esser, De-clicker, Stereo, Dereverb.
- **Pickers** — Engine, Loudness target, Output format.

A control that doesn't apply to your current settings is **dimmed**.
For example the **Denoise** knob dims when the DeepFilterNet engine is
selected (DFN does its own denoise), and the compressor knobs dim when
**Enhance** is off or the profile is **Light**.

Changes take effect on the **next** clip you queue. Clips already
finished keep the settings they were cleaned with — re-queue a clip
(remove it and drop it again, or use the CLI) to apply new settings.

---

## 4. Presets

A **preset** is a saved bundle of the whole "sound" — profile, engine,
toggles, loudness target, and every knob value. (It does **not** include
the output format or output folder; those stay as your global
preferences.) Presets let you switch between, say, a podcast sound and a
voicemail-rescue sound in one click.

### Applying a preset

Click the preset name in the preset bar and choose one. The console
updates to match.

### Built-in presets

PurpleVoice ships with eight, covering the common cases:

| Preset | Good for |
|---|---|
| **Voice Memo Cleanup** | The default. Everyday iPhone voice memos. |
| **Podcast** | Spoken-word episodes; de-esser on, normalized to −16 LUFS. |
| **Interview / Remote Call** | Noisy Zoom/phone interviews; aggressive denoise + de-ess. |
| **Lecture / Meeting** | Talks and meetings; de-clicker on, normalized to −14 LUFS. |
| **Audiobook / Narration** | Tighter compression for even narration; −14 LUFS. |
| **Field Recording** | Minimal processing, stereo preserved — keep it natural. |
| **Phone / Voicemail Rescue** | Thin, noisy phone audio; higher high-pass + aggressive denoise. |
| **Max Denoise (Neural)** | Hardest cleanup using DeepFilterNet + dereverb. |

Built-ins can't be edited or deleted, but you can **duplicate** one as
the starting point for your own.

### Saving your own

1. Set the console how you like it.
2. Open the **⋯** menu in the preset bar → **Save as New Preset…**
3. Name it. It now appears under **My Presets**.

When you tweak a control after applying a preset, the bar shows a
**Modified** badge. From the **⋯** menu you can then:

- **Update "<name>"** — write your changes back into that preset (your
  presets only).
- **Revert to "<name>"** — discard the tweaks and restore the preset.

### Managing presets

**⋯ → Manage Presets…** (or **Settings → Presets**) opens the manager:

- **Rename** a preset (your own) by editing its name field.
- **Duplicate** any preset, built-in or yours.
- **Delete** your own presets.
- **Apply** any preset.
- **New from current settings** — save the current console as a preset.

Your presets persist across launches and are shared with the
command-line tool.

---

## 5. Profiles, engines & loudness

### Profile (denoise strength)

| Profile | When to use |
|---|---|
| **Light** | Already-clean recordings — gentle de-hiss, no dynamics. |
| **Medium** | The default. A voice memo from a normal room. |
| **Aggressive** | Loud, noisy recordings — café, car, street. Can sound "underwater." |

If Aggressive sounds artificial, drop to Medium. If Medium leaves too
much noise, try the **DeepFilterNet** engine before going Aggressive —
it usually beats ffmpeg-Aggressive without the artifacts.

### Engine

- **ffmpeg** (default, always available) — classic frequency-domain +
  non-local-means denoise. Fast, no extra install.
- **DeepFilterNet** — neural speech enhancement, noticeably better on
  real-world noise. Requires `cargo install deep_filter`. When selected,
  it does the denoise and the ffmpeg **Denoise** knob is dimmed.

### Loudness target

Normalizes the final level to a publishing standard:

| Target | Level | Use |
|---|---|---|
| **Off** | — | You'll normalize later. |
| **Podcast** | −16 LUFS | Apple Podcasts. |
| **Streaming** | −14 LUFS | Spotify / Apple Music / YouTube. |
| **Broadcast** | −23 LUFS | EBU R128. |

---

## 6. The knobs, one by one

Each knob shows the current value. **Drag up/down to turn it; double-click
to reset** to the profile default. A knob you haven't touched shows the
profile default in grey; once you override it, the value turns solid and
a small **↺** reset button appears.

| Knob | What it does | Range (default) |
|---|---|---|
| **High-pass** | Removes low rumble below this frequency. | 20–200 Hz (80) |
| **Denoise** | How hard the ffmpeg denoiser attenuates steady noise. Higher = cleaner but more artifacts. | 0–30 dB (8/12/20 by profile) |
| **De-ess** | Sibilance ("sss") reduction strength. Only applies when **De-esser** is on. | 0–1 (0.4) |
| **Comp thr** | Compressor threshold — level above which compression kicks in. More negative = more compression on quiet parts. | −60–0 dB (−22) |
| **Comp rat** | Compression ratio. 1:1 = off, 3:1 gentle, 10:1 heavy. | 1–20 (3) |
| **Limiter** | Brick-wall peak ceiling (0–1). Lower leaves more headroom. | 0.5–1.0 (0.97) |

The compressor and limiter knobs are part of the **Enhance** chain — if
you turn Enhance off, they're dimmed. The compressor is also off in the
**Light** profile.

### The level meters

Beside the waveform, two vertical meters labelled **in** and **out**
show the playback level (green → yellow → red, with a peak-hold tick).
Only the stream you're currently auditioning is live — the meter follows
the **Original / Cleaned** A/B switch.

---

## 7. Waveform, trimming & A/B preview

Select a clip to see its waveform — **Original** on top, **Cleaned**
below (once it's processed).

- **Play / seek** — press **Play** (or Space). Click anywhere on the
  waveform to jump there; drag the red playhead to scrub. Scrubbing is
  audible, like a tape transport.
- **Trim** — drag the two accent-coloured handles to select a region.
  Only that region is cleaned, and the trim is applied **before** the
  denoise, so trimming a long recording saves processing time. The
  header shows the trimmed span; **Clear Trim** removes it.
- **A/B preview** — the **Original / Cleaned** switch flips the audio
  source mid-playback without losing your position, so you can hear
  exactly what changed.

---

## 8. Settings

**PurpleVoice → Settings…** (⌘,) has four tabs:

- **General** — output folder, output format, default profile, the
  Enhance toggle, "Reveal output in Finder" after processing, and the
  app version.
- **Processing** — engine, loudness target, the cleanup toggles
  (de-esser, de-clicker, dereverb), and stereo preservation.
- **Presets** — the full preset manager (same as ⋯ → Manage Presets…).
- **Advanced** — DeepFilterNet binary path override + reachability
  check, ffmpeg status, and copy-paste install commands.

---

## 9. Command line

The `purplevoice` wrapper runs the exact same engine as the app.

```sh
purplevoice clean <input> [options]
purplevoice presets
purplevoice help
purplevoice version
```

### Common examples

```sh
purplevoice clean memo.m4a
purplevoice clean talk.mp4 -o talk_clean.wav -p aggressive --lufs podcast
purplevoice clean interview.wav --engine deepfilter --dereverb --stereo
purplevoice clean podcast.m4a --trim 5.0:1800.0 --lufs podcast --de-esser
purplevoice clean memo.m4a --preset Podcast
purplevoice clean memo.m4a --preset Podcast --denoise-db 18
```

### Presets from the CLI

`purplevoice presets` lists the available presets (built-in and the ones
you saved in the app). `--preset "<name>"` starts from that preset;
**any other flag you pass overrides** the preset's value. Names with
spaces need quoting.

### Options

| Flag | Meaning |
|---|---|
| `-o, --output <path>` | Output file (default: `~/Downloads/PurpleVoice/`). |
| `--preset <name>` | Start from a saved preset; other flags override it. |
| `-p, --profile <name>` | `light` \| `medium` \| `aggressive`. |
| `--no-enhance` | Skip the dynamics chain. |
| `-e, --engine <name>` | `ffmpeg` \| `deepfilter`. |
| `--lufs <preset>` | `off` \| `podcast` \| `streaming` \| `broadcast`. |
| `--de-esser` / `--no-de-esser` | Sibilance reduction. |
| `--de-clicker` / `--no-de-clicker` | Click / pop removal. |
| `--stereo` / `--mono` | Preserve stereo, or downmix to mono (default). |
| `--dereverb` / `--no-dereverb` | Reverb reduction (DeepFilterNet only). |
| `--trim <start>:<end>` | Seconds; either side may be empty (`:15`, `5:`). |
| `-f, --format <name>` | `m4a` \| `mp3` \| `wav`. |
| `--quiet` | Print only the output path. |

### Fine-tuning flags

Each mirrors a console knob and is validated against the same range:

| Flag | Knob | Default |
|---|---|---|
| `--highpass-hz <N>` | High-pass | 80 |
| `--denoise-db <N>` | Denoise | 8/12/20 by profile |
| `--de-esser-intensity <N>` | De-ess | 0.4 |
| `--compressor-threshold-db <N>` | Comp thr | −22 |
| `--compressor-ratio <N>` | Comp rat | 3 |
| `--limiter-ceiling <N>` | Limiter | 0.97 |

Out-of-range values exit with an error rather than being silently
clamped, so you'll always know what was applied.

---

## 10. Where files go

- **Cleaned output:** `~/Downloads/PurpleVoice/<name>_clean.<ext>`.
  Change the folder in **Settings → General**; collisions get a `_2`,
  `_3`, … suffix so nothing is overwritten.
- **Waveform cache:** `~/Library/Caches/PurpleVoice/` (safe to delete).
- **Settings & presets:** stored in macOS UserDefaults for the app.

---

## 11. Supported formats

**Input:** `m4a`, `aac`, `mp3`, `wav`, `aif`/`aiff`, `caf`, `mp4`,
`m4v`, `mov`. Video files are accepted; the cleaned **audio** is written
as a standalone audio file (the video is not re-muxed).

**Output:** `m4a` (AAC 192 kbps, default), `mp3` (VBR ~q2), `wav`
(PCM 16-bit). Audio is resampled to 48 kHz and downmixed to mono unless
you enable **Stereo**.

---

## 12. Troubleshooting

**"ffmpeg not found."** Install it (`brew install ffmpeg`) and click
**Re-check** in the main window. ffmpeg is required.

**DeepFilterNet says "Not found."** Install it
(`cargo install deep_filter`; needs `brew install rust`), then re-check
in **Settings → Advanced**. If it's installed somewhere unusual, set the
binary path there.

**The cleaned file sounds "underwater" or swirly.** That's
over-aggressive denoise. Drop the profile from Aggressive to Medium,
lower the **Denoise** knob, or switch to the **DeepFilterNet** engine,
which is gentler on the voice for the same amount of cleanup.

**A knob won't turn / is greyed out.** It doesn't apply to your current
settings — e.g. the Denoise knob is inactive under the DeepFilterNet
engine, and the compressor knobs need **Enhance** on (and a non-Light
profile). Enable the relevant option first.

**I changed settings but the cleaned file didn't change.** Settings
apply to the **next** clip queued. Remove the clip and add it again to
re-process with the new settings.

**A video came out as audio only.** That's expected — PurpleVoice emits
cleaned audio as a standalone file; it doesn't re-mux the video.
