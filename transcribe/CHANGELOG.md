# Changelog

All notable changes to transcribe will be documented in this file.

## [1.4.0] — 2026-04-27

### Changed

- **Breaking (soft):** when `-o` is omitted, transcribe now writes to `~/Downloads/transcribe/<input-basename>.<format>` (created on demand) instead of stdout. Implements the project-wide default-output convention captured in `PhantomLives/CLAUDE.md`.
- To preserve the previous stdout-only behavior (for piping into other tools), pass `-o -`. Example: `transcribe.py -i meeting.mp4 -o - | grep ...`.
- `-o <path>` (absolute or relative) continues to write to the specified path as before.

## [1.3.0] — pre-2026-04-27

Baseline. See `__version__` history in `transcribe.py` for prior changes.
