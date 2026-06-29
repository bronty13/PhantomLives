# Changelog

## [1.0.0] - 2026-06-29

Initial release.

- **List files older than a date threshold** under a source directory:
  `oldfiles SOURCE --older-than 1y` (default age field: **created**; switch with
  `--by modified|accessed`, or use an absolute `--before YYYY-MM-DD`).
- **Recursion control:** descends all levels by default; `--max-depth N` limits
  depth (`0` = source's own files only). `--include-hidden` and
  `--follow-symlinks` opt in to dotfiles and symlinked dirs.
- **Filters:** `--ext`, `--glob`, `--min-size`.
- **Dry-run by default** — lists matches and the reclaimable total; deletes
  nothing without an explicit action flag.
- **`--delete`** moves matches to the Trash (recoverable; via Send2Trash, lazily
  bootstrapped into a local `.venv`). **`--delete-permanent`** removes them with
  stdlib `os.remove` (the option that actually frees space). Confirmation prompt
  unless `--yes`; refuses to delete in a non-interactive shell without `--yes`.
- **Protected-path guard** (realpath-resolved) refuses to scan-as-source or
  delete filesystem roots, OS system folders, the home root, `~/Library`,
  `/Volumes`, etc. Only regular files are ever deleted.
- **Output:** human table, `--json`, `--print0`, `--sort {age,size,name}` /
  `--reverse`, and `--report {csv,json,txt}` to `~/Downloads/oldfiles/`.
- Purpose: the **manual reclamation step** after PurpleAttic's `pattic` ad-hoc B2
  backup is verified. No automated/scheduled invocation by design.
- 23 stdlib `unittest` tests (`python3 test_oldfiles.py`).
