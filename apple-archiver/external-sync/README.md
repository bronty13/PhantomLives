# external-sync — pull-model archive of a remote Mac's Apple data

Orchestration for archiving a **remote Mac's** Apple data (Photos, Messages, Mail, Notes,
Reminders, Safari, Voice Memos, Calls, Calendar, Books, Podcasts, Stickies) to a local drive,
**pull-model** over SSH. The runner SSHes into the source Mac, runs the export there, and pulls the
result back. It drives the stdlib archivers in the parent [`apple-archiver/`](../) directory.

These scripts were previously deployed-only (on the runner) and **uncommitted** — a real
bus-factor/data-loss risk. They now live here. **Only the config carries PII, and that stays out of
git** (see below).

## Files

| File | Role |
|---|---|
| `external-<kind>-sync.sh` (13) | one per data type — SSH to the source, export, pull, stage NEW items for review |
| `source-vars.py` | reads `external-sources.json`, emits `SRC_*` shell vars for one source (`--list` lists ids) |
| `status-check.sh` | health/status summary across sources |
| `external-sources.example.json` | **template** — copy to `external-sources.json` and fill in real (PII) values |

The scripts are **generic** (no hardcoded hosts/users/paths) — everything comes from the config.

## Deploy

1. Copy the scripts + `source-vars.py` to the runner (historically
   `~/Library/Application Support/PurpleAttic/`). Keep them executable.
2. Copy `external-sources.example.json` → `external-sources.json` **on the runner only** and fill in
   the real host / user / identity file / remote paths. Do **not** commit that file (it's gitignored).
3. Install a launchd agent per job (`com.<owner>.external-<kind>-sync.<id>`) invoking
   `/bin/bash external-<kind>-sync.sh <id>`. Set `EnvironmentVariables.HOME` to the **runner's** home
   (the classic cross-Mac gotcha: a bare `HOME=/Users/<other-user>` breaks every path).
4. `archiveBase` in the config picks the destination drive — repoint it to migrate hosts (jobs re-read
   the JSON every run; no plist reload needed).

## Photo window (`windowDays`)

`photos.windowDays: N` caps the photo pull to files whose mtime is within the last N days
(osxphotos exports with `--touch-file`, so mtime = photo date). The archive still accumulates
everything new going forward (no `--delete`); the window only bounds the initial seed so a fresh
target isn't flooded with years of history. `0`/absent = unlimited (full mirror).

## Notes

- **Preservation-only:** no `--cleanup` / no `rsync --delete` — nothing is ever removed from the
  archive, even if deleted on the source. The window bounds the *pull*, not retention.
- Review staging: each run stages genuinely-new items into `<reviewBase>/<Name> NEW … TO REVIEW/` for
  triage (e.g. via PeekServer). A `.baseline_done` marker gates first-run catch-up vs. ongoing staging.
- Keep the real `external-sources.json`, `profile.json`, `settings.json`, and `*.log` on the runner
  only — they hold PII/state and are gitignored here.
