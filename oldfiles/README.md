# oldfiles

A small, scriptable CLI that **lists — and optionally purges — files older than a
date threshold**. It's the headless companion to PurpleTree's GUI.

Its primary purpose in this repo is the **post-backup reclamation step**: after
PurpleAttic's `pattic` ad-hoc Backblaze B2 backup has run and you've *verified*
the copies, point `oldfiles` at the source folder to purge the aged local
originals and reclaim disk space.

> **Reclaim-space note.** `--delete` moves files to the **Trash**, which still
> occupies disk until you empty it. To *actually free space* after a verified
> backup, use **`--delete-permanent`**.

## Safety model

This tool deletes files, so the defaults are deliberately conservative:

- **Dry-run by default.** With no action flag it only *lists* matches and shows
  the reclaimable total. Nothing is deleted.
- **`--delete`** → moves matches to the Trash (recoverable via Finder's *Put
  Back*; uses [Send2Trash](https://pypi.org/project/Send2Trash/)).
- **`--delete-permanent`** → `os.remove` (irreversible; the one that frees space).
- A **protected-path guard** refuses to scan-as-source or delete filesystem
  roots, OS system folders, the home root, `~/Library`, `/Volumes`, etc. — even
  if you point the tool straight at them. Paths are realpath-resolved first so
  symlink/`..` tricks can't dodge it.
- Deletion **asks for confirmation** unless `--yes`, and **refuses to delete in a
  non-interactive shell** without `--yes` (a stray pipe can't purge silently).
- Only **regular files** are ever deleted — directories and symlinks are left
  alone.

## Install

```bash
./install.sh            # installs `oldfiles` to ~/.local/bin (no sudo)
./install.sh --system   # installs to /usr/local/bin (sudo)
```

Or just run it in place — no install needed: `python3 oldfiles.py …`.
(`--delete` lazily creates a local `.venv` with Send2Trash on first use; listing
and `--delete-permanent` are pure stdlib.)

## Usage

```
oldfiles SOURCE [options]
```

### Age criteria
| Flag | Meaning |
|---|---|
| `--older-than DURATION` | Match files older than this. **Default `1y`.** Units: `y mo w d h` (e.g. `6mo`, `90d`, `48h`; a bare number = days). |
| `--before YYYY-MM-DD` | Match files older than an absolute date (overrides `--older-than`). |
| `--by {created,modified,accessed}` | Which timestamp to age by. **Default `created`** (`st_birthtime` on macOS). |

### Recursion
| Flag | Meaning |
|---|---|
| `--max-depth N` | Descend at most N levels below SOURCE. `0` = SOURCE's own files only. **Default: unlimited** (all levels deep). |
| `--follow-symlinks` | Follow symlinked directories (default: off). |
| `--include-hidden` | Include dotfiles / dot-directories (default: skip). |

### Filters
| Flag | Meaning |
|---|---|
| `--ext log,tmp,zip` | Only these extensions. |
| `--glob '*.log'` | Only names matching this glob. |
| `--min-size 100M` | Only files at least this big (`K/M/G/T`, 1024-based). |

### Actions (default: list only)
| Flag | Meaning |
|---|---|
| `--delete` | Move matches to the Trash (recoverable; still on disk until emptied). |
| `--delete-permanent` | Permanently delete matches (frees space now). |
| `-y`, `--yes` | Skip the confirmation prompt. |

### Output
| Flag | Meaning |
|---|---|
| `--sort {age,size,name}` | Sort order (default `age` — oldest first). `--reverse` to flip. |
| `--report {csv,json,txt}` | Also write a report to `~/Downloads/oldfiles/` (or `--output PATH`). |
| `--json` | Print results as JSON to stdout. |
| `-0`, `--print0` | NUL-separated paths to stdout (`xargs -0` friendly). |
| `-q`, `--quiet` | Suppress the table/summary. |

## Examples

```bash
# Preview everything older than a year (safe — lists only):
oldfiles ~/Downloads --older-than 1y

# Logs not modified in 90 days, only two levels deep:
oldfiles ~/Logs --older-than 90d --by modified --max-depth 2

# The post-pattic-backup reclaim: purge verified, year-old staged originals:
oldfiles /Volumes/REDONE/StagedForB2 --older-than 1y --delete-permanent --yes

# Hand the list to another tool:
oldfiles ~/tmp --older-than 30d -0 | xargs -0 du -sh
```

## Default output location

Reports (`--report`) default to **`~/Downloads/oldfiles/`** per the repo
convention, created on demand. Override with `--output PATH`.

## Tests

```bash
python3 test_oldfiles.py   # 23 tests, pure stdlib (unittest)
```

## Relationship to other PhantomLives tools

- **PurpleTree** — the interactive GUI for disk-space analysis and cleanup
  (Large & Old Files view, right-click delete). `oldfiles` is its scriptable,
  headless equivalent for the by-age purge.
- **PurpleAttic / `pattic`** — the ad-hoc B2 backup. `oldfiles` is the *manual*
  reclamation step you run **after verifying** a backup. (No automated/scheduled
  invocation for now — run it by hand.)
