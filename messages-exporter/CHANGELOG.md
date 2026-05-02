# Changelog

All notable changes to `messages-exporter` are recorded here.

## 1.3.2 — 2026-05-01

### Added
- `--debug` flag. When set, the transcription subprocess receives
  `HF_HUB_DISABLE_PROGRESS_BARS` and `TQDM_DISABLE` unset (so
  HuggingFace file-fetch progress bars, pip install output, and Whisper
  model-load bars are all visible). In the default (non-debug) mode those
  env vars are set to `1` so the subprocess is silent on known-noisy
  progress output.
- `TQDM_DISABLE=1` and `HF_HUB_DISABLE_PROGRESS_BARS=1` injected into
  the `transcribe_attachment()` child env for every non-debug run, on
  top of the existing `PYTHONUNBUFFERED=1`. This suppresses the
  "Fetching N files" HuggingFace model-cache check bars that tqdm
  renders even when the model is already on disk.
- Secondary tqdm line filter in the transcription streaming loop: any
  line containing `it/s]`, `it/s,`, `█`, or matching `%|` is silently
  dropped in non-debug mode. Defense-in-depth for libraries that use
  tqdm internally but don't check `TQDM_DISABLE` (e.g. older
  huggingface-hub versions).

### Changed
- `export_raw()` signature gains a `debug=False` parameter and threads
  it through to every `transcribe_attachment()` call.

## 1.3.1 — 2026-05-01

### Fixed
- `--transcribe` failed silently with a misleading "input file not
  found" message when transcribe.py crashed during its bootstrap
  (e.g. truststore unavailable on Python 3.9, mismatched .venv ABI,
  PEP 604 union syntax on a too-old interpreter). Two changes:
  - **Python 3.10+ probe**: messages-exporter now searches a list of
    well-known brew/system locations (and falls back to PATH) for a
    Python 3.10+ to invoke transcribe.py, instead of reusing its own
    venv interpreter. Override with `$TRANSCRIBE_PYTHON`. Returns a
    clear "no Python 3.10+ found" error to the per-attachment record
    rather than crashing transcribe.py.
  - **Better error classification**: an explicit `Error: …` line from
    transcribe.py is surfaced verbatim; a Python traceback is shown
    as `transcribe.py crashed: …` with the last few lines so the
    actual failure is visible; the exit-code mapping is now a
    fallback rather than the default. Captures up to 600 chars of
    tail (was 300) so the truncation doesn't cut off paths.

### Added
- `find_python_for_transcribe()` and `_python_at_least(path, M, m)`
  helpers, with new test cases (`TestPythonAtLeast`,
  `TestFindPythonForTranscribe`).
- `TestTranscribeAttachment` regressions:
  `test_python_traceback_classified_as_crash_not_misleading_label`,
  `test_explicit_error_line_is_surfaced_verbatim`,
  `test_no_python_available_returns_actionable_error`,
  `test_exit_code_3_with_no_explicit_error_falls_back_to_mapping`.

## 1.3.0 — 2026-05-01

### Added
- `--transcribe` flag: post-processes each audio/video attachment
  through the sibling `PhantomLives/transcribe/` project (Apple-MLX
  Whisper, Metal-accelerated, all local). Writes
  `<attachment>.transcript.json` (segments with timestamps) and
  `<attachment>.transcript.txt` (segment text joined by newlines,
  synthesized locally from the JSON) next to each audio/video
  attachment. Works in both raw and sanitized modes.
- `--transcribe-model` flag (default `turbo`, choices include `tiny`,
  `base`, `small`, `medium`, `large`). `turbo` is near-large quality
  at ~8x the throughput.
- In raw mode, both transcript sidecars are hashed (md5/sha1/sha256)
  and recorded in `metadata.json` (under
  `attachments[].transcript.hashes.{txt,json}`) and
  `chain_of_custody.log` (one `TRANSCRIBE` line per success carrying
  all hashes + sizes + duration_seconds). On failure the attachment's
  `transcript` field captures the structured error and a
  `TRANSCRIBE_FAILED` line is written to the log; the export
  continues.
- In sanitized mode, transcript sidecars land next to the saved
  attachment in `attachments/`, and `manifest.json` carries a per-
  attachment `transcript` object with hashes when successful.
- `metadata.json` (raw mode) gains an `export.transcribe` block
  documenting whether transcription was enabled, the model used, and
  the resolved transcribe.py path.

### Helpers
- `is_transcribable(mime, ext)` — recognizes audio (.mp3, .m4a, .wav,
  .aac, .flac, .ogg, .opus, .aiff, .aif, .caf, .amr, .wma) plus any
  video classified by `knd()` plus any `audio/*` MIME type.
- `find_transcribe_script()` — resolves transcribe.py via
  `$TRANSCRIBE_SCRIPT` env override or the default
  `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py`.
- `transcribe_attachment(...)` — Popen-based wrapper that streams
  stdout+stderr through to our stdout in real time (so the GUI log
  pane shows Whisper progress while the model crunches), maps
  documented exit codes (1=missing, 2=deps, 3=ffmpeg-decode,
  4=transcription error, 130=interrupted) to short reason strings,
  and writes the .txt sidecar from the JSON segments to avoid a
  second Whisper pass.

### Tests
- `TestIsTranscribable` (mime + ext, audio + video + photo + other
  cases), `TestFindTranscribeScript` (env override, missing path,
  default fallback), `TestTranscribeAttachment` (mocked Popen):
  missing-script error, success with segments → synthesized .txt,
  success with no segments → top-level text, exit 3 → ffmpeg-decode
  error mapping, exit 2 → mlx-whisper dependency error, exit 0 with
  no JSON → treated as failure.

## 1.2.0 — 2026-05-01

### Added
- Raw / forensic mode now records **MD5, SHA-1, and SHA-256** for every
  exported artifact (attachments and message bodies). All three are
  computed in a single streaming pass over the file and written to:
  - `metadata.json` — per-attachment `hashes={md5,sha1,sha256}` and
    per-message `body_hashes={md5,sha1,sha256}`.
  - `chain_of_custody.log` — every COPY and WRITE_BODY record carries
    `md5=… sha1=… sha256=…` alongside size.
  SHA-256 remains the primary integrity primitive; MD5 and SHA-1 are
  included for compatibility with older forensic tooling and historical
  chain-of-custody reports.
- `hashes_file(path)` helper replaces `sha256_file(path)`. Returns a
  dict with all three hex digests; previous callers compute all three
  for the same I/O cost as one.

### Changed
- `metadata.json` schema: per-attachment `sha256` field replaced with
  `hashes` dict; per-message `body_sha256` replaced with `body_hashes`
  dict. The compact `manifest.json` still surfaces `sha256` only (for
  quick diff-vs-export checks) — the full hash set lives in
  `metadata.json`. The transcript line still shows the truncated
  SHA-256 prefix for readability; full hashes are in the log.

### Tests
- Renamed `TestSha256File` → `TestHashesFile`; new known-vector cases
  for MD5 and SHA-1 of empty input and `abc`; large-file pass through;
  hex-case + alphabet check.
- `TestExportRawSmoke` updated to assert the new metadata schema and
  the new chain-of-custody log format with all three hashes.

## 1.1.1 — 2026-05-01

### Fixed
- Defensive deduplication of the message SELECT. The original query
  joined `message` against `chat_message_join` without grouping, which
  meant a message present in multiple cmj rows (rare but real on
  databases that have been through handle migrations or forwarded
  deliveries) was returned and exported once per join row, inflating
  the output beyond the user-specified date range. `GROUP BY m.ROWID`
  collapses those rows to one per message regardless of cmj
  multiplicity.

### Added
- Stage-3 diagnostic output: prints the start/end bounds in both
  human-readable local time and Mac-epoch nanoseconds, and the
  first/last message's `m.date` value as it appeared in the SELECT.
  Includes a sanity check that flags any returned message whose date
  falls outside the bounds (would indicate a future seconds-vs-
  nanoseconds heuristic mismatch or a query regression).

## 1.1.0 — 2026-05-01

### Added
- `--raw` flag for forensic exports. Output goes to
  `<contact>_<YYYYMMDD_HHMMSS>_raw/` with a flat directory layout: each
  message's body becomes `[seq]_[YYYYMMDDTHHMMSS]_[sender].txt` and each
  attachment is copied byte-for-byte under
  `[seq]_[YYYYMMDDTHHMMSS]_[sender]_[orig_filename]`. No HEIC→JPG, no
  EXIF/GPS strip, no `.jpeg`→`.jpg` normalization — the bytes that
  arrive on disk are identical to the source under
  `~/Library/Messages/Attachments/`.
- `metadata.json` written in raw mode. Per-message: timestamps (UTC +
  local), sender label and handle, body and `body_sha256`. Per-attachment:
  original filename, source path, mime type, kind, saved-as name,
  `size_bytes`, `sha256`, `fs_timestamps` (`mtime`, `ctime`, `birthtime`
  when available), and an `exif` dump from `exiftool -json -G -n` (read-
  only — the source file is not modified).
- `chain_of_custody.log` written in raw mode. Append-only line per
  action: `START`, `VERSION`, `WRITE_BODY` (with sha256 + size), `COPY`
  (with src, dest, sha256, size), `MISSING_SOURCE`, `COPY_FAILED`, and
  `END` (with counts). Every line begins with an ISO-8601 UTC timestamp.
- Helper functions `sha256_file`, `fs_stat`, `exiftool_version`,
  `extract_exif`, `raw_prefix`, and `export_raw` (extracted from
  `main()` so the raw path can be unit-tested without `chat.db`).

### Tests
- `TestSha256File` (empty file, `abc` known vector, multi-MiB chunked).
- `TestFsStat` (size + ISO-parseable timestamps).
- `TestRawPrefix` (`Me`, handle, contact fallback, unknown, sanitization,
  zero-padding).
- `TestExportRawSmoke` end-to-end test of `export_raw()` with synthetic
  msgs/atts: asserts directory layout, sha256 capture, `metadata.json`
  structure, and chain-of-custody log content. Also covers the
  `MISSING_SOURCE` error path.

## 1.0.1 — 2026-04-24

### Fixed
- Caption extraction now strips U+FFFC (Object Replacement Character),
  which iMessage inserts as a placeholder for inline attachments. Previously
  this leaked into filenames as a visible `￼` glyph in `--emoji keep` mode
  and into the transcript/manifest body in all modes.

### Tests
- Added `get_body` coverage for messages whose `text` column or
  `attributedBody` string contains U+FFFC, asserting the placeholder is
  removed while real content is preserved.

## 1.0.0 — 2026-04-24

Initial release.

### Added
- Export iMessage conversations by contact name and date range.
- Contact resolution via the AddressBook SQLite database (phones + emails).
- `attributedBody` parsing so captions stored in the binary NSKeyedArchiver
  blob (rather than the plain `text` column) are recovered.
- Caption-based filename assignment: each media attachment is named after
  the first text-bearing message that follows it.
- HEIC → JPG conversion with a PIL + pillow_heif primary path and a macOS
  `sips` fallback. `.jpeg` is normalized to `.jpg`.
- Metadata sanitization:
  - Images: `exiftool -all=` (preferred, lossless) or PIL re-save.
  - Videos: `ffmpeg -map_metadata -1 -c copy` (lossless).
- Emoji handling modes for filenames: `strip`, `word` (default), `keep`.
  Word mode uses the `emoji` library to map 🔥 → `(fire)`.
- Single flat `attachments/` folder for all photos, videos, and files
  (instead of three separate subdirectories).
- Transcript (`transcript.txt`), manifest (`manifest.json`), and summary
  (`summary.txt`) artifacts per run.
- `--version` flag and a startup banner that prints detected capabilities,
  the Python interpreter path, and actionable install hints for anything
  missing.
- Loud warning when `--emoji word` is requested but the `emoji` library is
  not importable in the current interpreter (previously a silent fallback
  to strip mode).
- `install.sh` with `--system`, `--upgrade`, and `--uninstall` modes.
  Installer creates a dedicated venv at `~/.venvs/messages-exporter` and
  bakes that venv's Python into the installed script's shebang so the
  command is self-contained.
- `test_export_messages.py` unit-test suite covering pure-function
  behavior.
