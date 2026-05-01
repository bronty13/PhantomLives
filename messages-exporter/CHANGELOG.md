# Changelog

All notable changes to `messages-exporter` are recorded here.

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
