# PurpleSpeak

A Speechify-style **read-aloud** and **transcription** app for macOS — fully
on-device, private, and offline. Drop in a PDF, EPUB, Word doc, web article, or
image and PurpleSpeak reads it aloud, lighting up each word as it speaks. Drop
in an audio or video file and it transcribes it with Whisper.

No cloud round-trip, no account, no telemetry. Apple's on-device voices and
Vision OCR plus a Homebrew `whisper.cpp` do all the work locally.

## What it does

### Read anything aloud
- **Synced word highlighting** — the spoken word lights up and its sentence
  glows, scrolling to follow along. The signature feature of every great
  reader, done with Apple's built-in speech engine.
- **On-device voices** — every system voice (Default / Enhanced / Premium) and
  your Personal Voice. Pick one, set the speed (0.5–4×) and pitch.
- **Open almost anything** — PDF (with OCR fallback for scans), EPUB, Word
  (`.docx`/`.doc`), RTF, HTML, Markdown, plain text, **web articles** (paste a
  link), and **images** (OCR via Vision).
- **Reading comfort** — adjustable font size / line spacing and a line-focus
  mode that dims everything but the paragraph being read.
- **Export to audio** — save the narration as `.m4a` (or `.mp3` with `lame`)
  for offline / commute listening.

### Transcribe speech to text
- Drop an audio or video file → an editable, timestamped transcript via
  on-device **whisper.cpp**.
- Export `.txt` / `.srt`, or **Send to Reader** to listen back.
- Whisper models download on demand from Settings → Transcription.

## Quick start

```sh
cd PurpleSpeak
./build-app.sh        # build + install to /Applications + relaunch
```

`build-app.sh` builds `PurpleSpeak.app`, installs it to `/Applications/` (via
`install.sh`, with a stale-instance freshness proof), and relaunches it. Flags:
`--no-install`, `--no-open`, or `BUILD_ONLY=1`.

To enable on-device transcription, install whisper.cpp — the app runs the
Homebrew `whisper-cli` as a subprocess at runtime:

```sh
brew install whisper-cpp     # provides `whisper-cli`
```

The app runs fine without it — the Transcribe panel just guides you to install
it. (whisper.cpp isn't bundled: ggml loads its compute backends as separate
plugins that don't survive being copied into an app bundle — see HANDOFF.md.)

### Tests

```sh
./run-tests.sh        # Swift Testing — 13 tests
```

## Where things go

| What | Where |
|---|---|
| Exported audio & transcripts | `~/Downloads/PurpleSpeak/` (overridable in Settings → Output) |
| Automatic backups | `~/Downloads/PurpleSpeak backup/` |
| Library, settings, Whisper models | `~/Library/Application Support/PurpleSpeak/` |

## Documentation

- **[USER_MANUAL.md](USER_MANUAL.md)** — full walkthrough of every feature.
- **[CHANGELOG.md](CHANGELOG.md)** — version history.
- **[HANDOFF.md](HANDOFF.md)** — architecture snapshot for maintainers.

## Requirements

macOS 14+ (Apple Silicon recommended for transcription). Built with SwiftPM +
SwiftUI; no third-party Swift dependencies.
