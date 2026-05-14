# Changelog

All notable changes to transcribe will be documented in this file.

## [1.4.4] — 2026-05-14

### Fixed
- **Self-heal venvs left in the empty-package-directory state.** 1.4.3's
  bootstrap correctly skipped `pip install` when every required module
  imported cleanly, but if the venv was already partially corrupted
  (the canonical "interrupted pip uninstall left `__pycache__` and
  `*.dist-info` behind while the `.py` files are gone" state), it still
  fell back to `pip install` on top of the broken state — which itself
  failed when pip was among the half-deleted packages. The net effect:
  back-to-back invocations all hit a fresh `CalledProcessError` on the
  same broken venv.
- New behaviour: when `_required_modules_importable()` returns False
  on an existing venv, `_bootstrap_venv` now **nukes and recreates the
  venv** before running pip install. Pip install never runs on top of
  a venv that didn't pass the import probe — clean slate is the only
  reliable recovery from this state. We've confirmed this with the
  exact reproducer (manually deleting `pip/_internal/utils/*.py` to
  simulate the corruption): the bootstrap auto-detects, prints
  `Rebuilding /…/.venv (required modules don't import — assuming
  partial-install corruption) ...`, rebuilds, and re-execs in the
  same invocation.

## [1.4.3] — 2026-05-14

### Fixed
- **Intermittent `_bootstrap_venv` failures during batched invocations.**
  Root cause: `_bootstrap_venv()` ran `pip install` *unconditionally*
  on every invocation, even when the venv was fully populated with
  every entry in `REQUIRED_PACKAGES`. Across a batch of N back-to-back
  invocations (e.g. one transcribe.py call per attachment in a 42-msg
  iMessage export) this turned into N independent dice rolls for "did
  the network and PyPI behave?" — and the user saw random
  `subprocess.CalledProcessError`s bubbling up from `_bootstrap_venv`
  mid-batch even though every package was already installed. The
  in-line comment said "subsequent runs pip-check silently" but the
  code did no such thing.
- New behaviour: `_required_modules_importable()` probes whether
  `VENV_PYTHON` can `import` every entry in `_REQUIRED_IMPORTS` (a new
  module-name companion list kept in sync with `REQUIRED_PACKAGES`).
  If it can, the bootstrap skips `pip install` entirely — no network
  round trip. If anything's missing, `pip install` runs as before, so
  the genuine first-run / partial-install paths still work. Verbose
  mode (`-v`/`--verbose`) prints `"Dependencies already installed —
  skipping pip install."` for confidence.

### Changed
- `_bootstrap_venv` no longer hits PyPI at all in the steady state.
  Concretely: an idle bootstrap (everything already installed) now
  takes ~50 ms of import-probe time instead of a multi-second
  PyPI round trip per invocation.

## [1.4.2] — 2026-05-01

### Fixed
- **First-run detection bug in `_bootstrap_venv()`**: `first_run` was
  being captured *after* `venv.create()`, so it always evaluated
  `False` and the "Installing dependencies" message was never shown
  even on a clean install. Moved the check before the `venv.create()`
  call.
- pip install output now redirected to `subprocess.DEVNULL` when not
  in verbose mode (`-v` / `--verbose`). Previously all "Requirement
  already satisfied" lines were printed on every run after the first,
  causing significant noise in GUI log panes and CI output.
- Added `--progress-bar off` to the pip install call so no tqdm
  progress bars leak through even when output is not fully suppressed.

### Changed
- All `log()` calls now pass `flush=True` so each line is flushed
  immediately. Required for real-time streaming when transcribe.py is
  invoked as a subprocess through a pipe (Python block-buffers stdout
  when connected to a pipe unless explicitly flushed or
  `PYTHONUNBUFFERED=1` is set by the caller).
- Reduced normal-mode log verbosity:
  - `transcribe_audio()` no longer logs the full HuggingFace repo ID
    or RAM-usage estimate; those move to verbose-only output. The
    normal-mode line is simply `Transcribing with model '<name>' ...`.
  - The completion line now logs only the basename of the output file
    (`Transcript: <file>`) rather than the full absolute path.
  - HuggingFace repo ID and RAM hint are still shown in verbose mode.

## [1.4.1] — 2026-05-01

### Fixed
- Fail fast with a clear error when invoked under Python <3.10 (the
  script uses PEP 604 union syntax and pulls in `mlx>=0.16` which has
  no wheels for older interpreters). Previous behavior was an
  unhelpful `TypeError: unsupported operand type(s) for |` on parse.
- Detect a stale `.venv` whose internal Python is <3.10 and rebuild
  it on the next run. Earlier .venvs created under CommandLineTools
  3.9 silently broke the bootstrap pip install once the script
  started requiring 3.10+; deleting and recreating is cheaper than
  asking users to `rm -rf .venv` manually.
- `truststore>=0.10.0` is now installed only on Python ≥3.10. It's
  already imported under `try/except ImportError`, so older
  interpreters that can't host the wheel skip it cleanly. (3.9 venvs
  no longer trip the bootstrap pip install on this dep.)

## [1.4.0] — 2026-04-27

### Changed

- **Breaking (soft):** when `-o` is omitted, transcribe now writes to `~/Downloads/transcribe/<input-basename>.<format>` (created on demand) instead of stdout. Implements the project-wide default-output convention captured in `PhantomLives/CLAUDE.md`.
- To preserve the previous stdout-only behavior (for piping into other tools), pass `-o -`. Example: `transcribe.py -i meeting.mp4 -o - | grep ...`.
- `-o <path>` (absolute or relative) continues to write to the specified path as before.

## [1.3.0] — pre-2026-04-27

Baseline. See `__version__` history in `transcribe.py` for prior changes.
