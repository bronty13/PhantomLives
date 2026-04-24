# Changelog

All notable changes to `messages-exporter` are recorded here.

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
