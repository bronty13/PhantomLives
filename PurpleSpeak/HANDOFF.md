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

`ReaderView` hosts `ReaderTextView` — an `NSTextView` (TextKit) wrapped in
`NSViewRepresentable`. TextKit is what enables **word-precise click-to-start**:
SwiftUI `Text` can't map a click to a character index, but
`NSLayoutManager.characterIndex(for:)` can (see `CenteringTextView.mouseDown`),
and `ReaderTextView.wordStart(in:at:)` snaps it to the enclosing word →
`AppState.startReading(from:)`. Highlighting is applied as **minimal-diff
attribute edits** on the text storage (only the changed word/sentence ranges per
spoken step — never rebuilding the string), with `scrollRangeToVisible` for
auto-scroll and native text selection preserved. Line-focus dims the document
foreground and re-lights the active sentence. `sentenceRange(containing:in:)`,
`AppState.paragraphStartOffsets`, and `ReaderTextView.wordStart` are pure/static
and unit-tested.

## Services

| File | Role |
|---|---|
| `TextExtractionService` | PDF (PDFKit), DOCX/RTF (`NSAttributedString`), EPUB (unzip + OPF spine + HTML strip), HTML, web articles (fetch + readability regex), plain text. HTML/EPUB paths are `@MainActor` (AppKit HTML reader). |
| `OCRService` | Vision `VNRecognizeTextRequest` over images and rasterized image-only PDF pages. |
| `AudioExportService` | `AVSpeechSynthesizer.write(_:toBufferCallback:)` → CAF → `.m4a` (AVAssetExportSession) or `.mp3` (shell `lame`). |
| `STTEngine` / `WhisperCppEngine` | Runs the **Homebrew** `whisper-cli` (`resolvedBinaryURL` prefers `/opt/homebrew/bin`); converts input to 16 kHz mono WAV via `afconvert`; parses bracketed timestamps. Graceful when the binary/model is absent. Not bundled — see "STT bundling" below. |
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

## STT bundling (why whisper-cli isn't in the .app)

We tried bundling `whisper-cli` + its dylibs (SlackSucker pattern) and hit two
walls: (1) re-signing the Homebrew dylibs under our identity trips a
hardened-runtime **Team-ID mismatch** when dyld maps them (fixable by rewriting
install names to `@rpath`), but (2) ggml loads its compute backends
(`libggml-cpu*/metal/blas.so`) as separate **`dlopen`'d plugins** discovered via
a hardcoded Cellar `libexec` path / `GGML_BACKEND_PATH` — a copied-into-bundle
binary finds none and aborts with `GGML_ASSERT(device) failed` (`backends = 0`).

Current approach: **run the original Homebrew `whisper-cli` as a subprocess**
(its own process, valid signatures, finds its own backends). STT therefore needs
`brew install whisper-cpp`. A self-contained bundle would mean copying the
backend `.so` plugins into Resources, fixing their `@rpath`s, re-signing them,
and setting `GGML_BACKEND_PATH` on the spawned process to point at them — doable
but version-fragile; left as future work.

## Known follow-ups (deferred from the competitive survey)

- Cloud premium voices (ElevenLabs/OpenAI) behind the existing `TTSEngine`
  protocol.
- MLX Whisper backend (shell out to the repo's `transcribe/`) behind
  `STTEngine`.
- Browser extension, read-it-later sync, speaker diarization.
