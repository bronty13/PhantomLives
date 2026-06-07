# PurpleSpeak — Architecture Handoff

A SwiftPM + SwiftUI macOS app. On-device TTS (read aloud) + STT (transcribe).
No third-party Swift dependencies. Read this before non-trivial changes.

## Mental model

```
PurpleSpeakApp (@main)
└── AppState (@MainActor, the coordinator)
    ├── SettingsStore        — AppSettings ↔ settings.json
    ├── DocumentStore        — Document[] ↔ library.json + per-doc .txt sidecars
    ├── AVSpeechTTSEngine     — TTSEngine; the synced-highlight source
    └── WhisperModelManager   — downloads GGML models
```

`AppState` owns these and they're injected into the SwiftUI environment
individually (so each `ObservableObject` is observed directly). Views call verbs
on `AppState`; `AppState` drives the services.

## The keystone: synced highlighting

`AVSpeechTTSEngine` (`Services/TTSEngine.swift`) wraps `AVSpeechSynthesizer`.
The whole document (or a tail of it, for click-to-start) is spoken as one
utterance. The delegate callback
`speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)` hands back the
character range of each word as it's spoken; we add `baseOffset` to map it into
whole-document coordinates and publish `spokenWordRange` /
`spokenSentenceRange`.

`ReaderView` renders the text **a paragraph at a time** (LazyVStack) so only the
active paragraph rebuilds its `AttributedString` on each word callback — the
word gets a bold yellow background, the sentence a faint purple one. It
auto-scrolls to the active paragraph. `sentenceRange(containing:in:)` and
`AppState.paragraphStartOffsets` are pure/static and unit-tested.

## Services

| File | Role |
|---|---|
| `TextExtractionService` | PDF (PDFKit), DOCX/RTF (`NSAttributedString`), EPUB (unzip + OPF spine + HTML strip), HTML, web articles (fetch + readability regex), plain text. HTML/EPUB paths are `@MainActor` (AppKit HTML reader). |
| `OCRService` | Vision `VNRecognizeTextRequest` over images and rasterized image-only PDF pages. |
| `AudioExportService` | `AVSpeechSynthesizer.write(_:toBufferCallback:)` → CAF → `.m4a` (AVAssetExportSession) or `.mp3` (shell `lame`). |
| `STTEngine` / `WhisperCppEngine` | Runs the bundled `whisper-cli`; converts input to 16 kHz mono WAV via `afconvert`; parses bracketed timestamps. Graceful when the binary/model is absent. |
| `BackupService` | Zip support dir → `~/Downloads/PurpleSpeak backup/`; debounce / retention / verify / restore. Lifted from Timeliner, de-GRDB'd. |
| `WindowStateGuard` | Copied verbatim from PurpleReel; sanitizes persisted window/split state on launch. |

## Build & version

- `build-app.sh`: SwiftPM build → assemble bundle in /tmp → **bundle + sign
  `whisper-cli` (and its dylibs) FIRST, then the app** → git-derived version
  stamp into the bundle's Info.plist → `ditto` back → chain into `install.sh`.
  whisper-cli is resolved from `$WHISPER_BIN` or PATH; absent = build without
  STT (the app degrades gracefully).
- `install.sh`: the four-step stale-instance proof (kill → replace → `open -n`
  → assert process-start ≥ binary-mtime). Prints `Verified: … running fresh`.
- Versions are git-derived (`1.0.<commit-count>`); `Version.swift` reads the
  bundle Info.plist at runtime.

## Persistence formats

- `library.json`: `[Document]`, encoded/decoded with **`.iso8601` dates on both
  sides** (mismatch = silent empty library — was an early bug).
- `settings.json`: `AppSettings` (pretty/sorted). Output/backup paths stored as
  `~/…` strings, expanded via `SupportPaths.expand`.
- Document text lives in `documents/<uuid>.txt` sidecars.

## Known follow-ups (deferred from the competitive survey)

- Cloud premium voices (ElevenLabs/OpenAI) behind the existing `TTSEngine`
  protocol.
- MLX Whisper backend (shell out to the repo's `transcribe/`) behind
  `STTEngine`.
- Word-precise click-to-start (currently paragraph granularity).
- Browser extension, read-it-later sync, speaker diarization.
