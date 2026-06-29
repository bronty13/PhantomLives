# oldfiles — User Manual

`oldfiles` finds files older than a date threshold under a folder and, when you
ask it to, deletes them. It is the command-line companion to PurpleTree, built
for one job in particular: **reclaiming disk space after a verified backup**.

The intended workflow:

1. Back up a folder with PurpleAttic's `pattic` ad-hoc B2 feature.
2. **Verify** the backup (restic/B2 check, spot-restore — whatever your habit is).
3. **Preview** the aged local originals: `oldfiles <folder> --older-than 1y`.
4. When the list looks right, **purge** them: add `--delete-permanent`.

Nothing is deleted in steps 1–3. The tool only deletes when you explicitly pass
an action flag in step 4.

---

## 1. The safe default: just list

```bash
oldfiles ~/Downloads --older-than 1y
```

This walks every level under `~/Downloads`, finds files whose **created** date is
more than a year old, and prints them with their age, size, date, and path — plus
a one-line summary of how many files and how much space they represent. **It
deletes nothing.** This is a *dry run*; run it as often as you like.

## 2. Choosing the age

- `--older-than DURATION` — the default is `1y`. You can say `6mo`, `90d`, `2w`,
  `48h`, or a bare number (which means days). "1 year" is treated as 365 days,
  "1 month" as 30 days — approximate by design.
- `--before YYYY-MM-DD` — instead of a relative age, match everything older than a
  specific calendar date. This overrides `--older-than`.
- `--by created|modified|accessed` — which timestamp to judge age by. The default
  is **created** (the file's birth time on macOS). Use `--by modified` if you
  care about when content last changed, or `--by accessed` for last-opened.

## 3. How deep to go

- By default `oldfiles` descends **all the way down** — every subfolder, any
  number of levels.
- `--max-depth N` limits it: `--max-depth 0` looks at only the files sitting
  directly in the folder (no subfolders); `--max-depth 2` goes two levels down;
  and so on.
- Hidden files and folders (names starting with `.`) are skipped unless you add
  `--include-hidden`. Symlinked folders are not followed unless you add
  `--follow-symlinks`.

## 4. Narrowing the list

- `--ext log,tmp,zip` — only those file types.
- `--glob '*.log'` — only names matching a pattern.
- `--min-size 100M` — only files at least that big (great for finding the actual
  space hogs).

## 5. Deleting

There are two delete modes, and the difference matters:

- **`--delete`** moves the files to the **Trash**. They're recoverable (Finder →
  *Put Back*), but **they still take up disk space until you empty the Trash.**
- **`--delete-permanent`** removes the files outright. This cannot be undone — and
  it's the option that **actually frees the space immediately.** For the
  reclaim-after-backup workflow, this is usually the one you want.

Before deleting, `oldfiles` shows you the count and total size and asks
`Continue? [y/N]`. Add **`-y` / `--yes`** to skip the prompt (for example in a
script you've already vetted). In a non-interactive shell (a pipe, a cron job),
`oldfiles` will **refuse to delete** unless `--yes` is present — so nothing gets
purged by accident.

```bash
# Preview, then purge a verified backup's year-old originals:
oldfiles /Volumes/REDONE/StagedForB2 --older-than 1y
oldfiles /Volumes/REDONE/StagedForB2 --older-than 1y --delete-permanent
```

## 6. Saving a record

- `--report csv|json|txt` writes the list to `~/Downloads/oldfiles/` with a
  timestamped filename (use `--output PATH` to choose your own). Handy to keep a
  record of exactly what you purged and when.
- `--json` prints the results as JSON to the screen; `-0` prints NUL-separated
  paths for piping into `xargs -0`.

## 7. What it will never do

- It refuses to run against — or delete — system locations: `/`, `/System`,
  `/usr`, `/var`, your home folder's root, `~/Library`, `/Volumes`, and similar.
- It only deletes **regular files**, never folders or symlinks.
- It never deletes anything in a dry run, and never deletes without your
  confirmation (or an explicit `--yes`).

## 8. Tips & limits

- Run the **same command twice** — once to preview, once with the delete flag.
  The preview is the safety net.
- "Created" time on non-macOS systems may not exist; there `oldfiles` falls back
  to modified time for `--by created`.
- Emptying the Trash after a `--delete` run is what reclaims the space; if you're
  chasing free space, prefer `--delete-permanent`.
