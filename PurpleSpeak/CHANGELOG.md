# Changelog

All notable changes to PurpleSpeak are documented here.

## 1.0.0 — Initial release (2026-06-06)

The first cut of PurpleSpeak: a Speechify-style read-aloud + transcription
app for macOS, fully on-device and private.

### Text-to-speech (reading)
- **Synced word highlighting** — the current word lights up and its sentence
  gets a soft purple glow, driven by `AVSpeechSynthesizer`'s
  `willSpeakRangeOfSpeechString` callback. Auto-scrolls to follow along.
- On-device voices via `AVSpeechSynthesizer` (system Default / Enhanced /
  Premium + Personal Voice). Defaults to the user's locale voice. The voice
  picker is grouped into per-language sections (localized names, your exact
  locale first) so it stays navigable across 100+ installed voices.
- Playback transport: play/pause, stop, previous/next paragraph, speed
  (0.5–4×), pitch, and a live voice picker.
- Reading-comfort controls: font size, line spacing, and a line-focus mode
  that dims everything but the active paragraph.
- Word-precise click-to-start: click any word to begin reading from exactly
  that word (TextKit-backed reading surface; also keeps native text selection).

### Import
- PDF (with OCR fallback for scanned PDFs), EPUB, DOCX/DOC, RTF/RTFD, HTML,
  Markdown, and plain text.
- **Web articles** — paste a link; a readability pass pulls the article text
  out of the page.
- **OCR** — drop an image (or image-only PDF) and Vision reads the text
  on-device.
- Drag-and-drop or the Import panel; a persistent library with rename / delete
  / reveal-original.

### Audio export
- Export narration to `.m4a` (AAC, default) or `.mp3` (when Homebrew `lame`
  is installed; otherwise falls back to M4A). Saves to
  `~/Downloads/PurpleSpeak/`.

### Speech-to-text (transcription)
- On-device transcription of audio/video via the Homebrew `whisper.cpp`
  (`whisper-cli`), run as a subprocess (`brew install whisper-cpp`). Editable,
  timestamped transcript; export `.txt` / `.srt`; "Send to Reader" to listen to
  a transcript. (Not bundled — ggml's compute-backend plugins don't survive
  being copied into an app bundle; see HANDOFF.md.)
- Whisper GGML models download on demand (Large v3 Turbo / Base.en / Small)
  into `~/Library/Application Support/PurpleSpeak/models/`.
- Optional: an MLX backend hook (reuses the repo's `transcribe/` tool) is
  scaffolded behind the `STTEngine` protocol for a future release.

### Platform / hygiene
- Manual `HStack` sidebar (not `NavigationSplitView`) per the repo standard,
  with `WindowStateGuard` + "Reset Window State…".
- Auto-backup-on-launch (zip of the app-support dir → `~/Downloads/PurpleSpeak
  backup/`, 14-day retention, 5-min debounce) + full Settings → Backup UI.
- Git-derived versioning; `build-app.sh` → build + install to `/Applications/`
  + relaunch with the four-step stale-instance freshness proof.
- 24 unit tests (highlight range mapping, paragraph offsets, whisper output
  parsing, SRT formatting, text normalization, filename sanitizing, settings
  round-trip, backup retention / listing / round-trip) — plus hermetic
  format-extraction round-trips on committed PDF/DOCX/RTF/EPUB/HTML/PNG
  fixtures (incl. web-article chrome-stripping), and audio-export round-trips
  covering the M4A path and the MP3/`lame` path with its M4A fallback.
