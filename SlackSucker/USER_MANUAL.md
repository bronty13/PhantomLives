# SlackSucker user manual

## First run

1. Build the app: `./build-app.sh` (requires `brew install slackdump` first).
2. Install: `./install.sh` — replaces `/Applications/SlackSucker.app` and relaunches.
3. In the running app, click **Manage…** in the sidebar's WORKSPACE section.
4. Click **Add workspace…**, optionally type a workspace URL (e.g. `https://yourteam.slack.com`) or leave blank for `default`, then click **Sign in**.
5. Slackdump's EZ-Login 3000 opens a browser window — sign in to Slack there. The sheet streams progress so you can see what's happening.
6. When the workspace appears in the list, click **Select** next to it. SlackSucker remembers your choice across launches.

## Archiving

The main pane has four sections:

- **What to archive**:
  - **Entire workspace** — every conversation your token can see
  - **Channel / DM** — type-ahead picker over the cached entity list (channels, DMs, multi-party DMs, users)
  - **Thread URL** — paste a Slack message permalink (e.g. `https://your.slack.com/archives/C123/p1700000000123456`)
- **Time range**: "Archive all time" or a from/to window. Pickers are local-time; SlackSucker converts to UTC for slackdump.
- **Options**:
  - **Download files** — fetch attachments alongside messages (default on)
  - **Avatars** — fetch user profile thumbnails to `__avatars/`
  - **Member-only channels** — workspace-wide runs only; skips channels you're not in
  - **Sort into Videos/Photos/Audio/Other** — post-process to organize attachments by media type (default on)
- **Run / Live output**: the blue gradient button kicks off the run. Output streams into the log card; chips along the top copy the buffer, reveal the run folder, open the SQLite database, or resume a cancelled run.

Each run writes to `~/Downloads/SlackSucker/<scope>_<YYYYMMDD_HHmmss>/`.

## Output layout

A successful run produces:

```
~/Downloads/SlackSucker/<scope>_<YYYYMMDD_HHmmss>/
├── slackdump.sqlite           Source of truth — slackdump's archive
├── archive.log                Every line slackdump streamed
├── organize-log.txt           FileOrganizer summary (file counts per category)
├── __avatars/                 User profile thumbnails (untouched)
├── Videos/                    .mp4 .mov .m4v .mkv .webm .avi …
├── Photos/                    .jpg .jpeg .png .heic .webp .gif .svg …
├── Audio/                     .mp3 .m4a .wav .ogg .flac .opus …
├── Other/                     Everything else (PDFs, docs, archives)
└── Chat/
    └── <scope>.txt            Plain-text transcript (channel/DM/thread only)
```

`Chat/<scope>.txt` is produced for channel, DM, and thread archives. **Whole-workspace runs skip the transcript** — too many conversations to flatten into one file. For that case, slackdump's own `slackdump view` or `slackdump convert -f html` is the better tool against the SQLite.

## Transcript format

Plain ASCII, greppable, renders cleanly in any editor:

```
SlackSucker chat export
Scope: #info-and-links
Workspace: default
Run folder: __info-and-links_20260515_135442
Generated: 2026-05-15T13:55:00
Messages: 3
------------------------------------------------------------

[2026-05-15 09:01:54] @rob
  @rob has joined the channel

[2026-05-15 09:02:15] @rob
  Main content folder https://www.dropbox.com/…
  [file] plan.pdf

    [2026-05-15 09:05:30] @Sallie
      Thanks!
```

- Thread replies indented 4 spaces under their parent
- `<@U…>` mentions resolved to `@displayname`
- `<#C…|channel>` to `#channel`
- `<https://…|label>` to `label`; bare `<https://…>` to the URL
- HTML entities (`&amp;`, `&lt;`, `&gt;`) decoded
- File attachments listed under their message as `[file] <filename>`
- Unknown user IDs fall back to `@U…` instead of crashing

## Channel cache

The Channel/DM picker reads from a cache at `~/Library/Application Support/SlackSucker/channel-cache/<workspace>.json`. To refresh, click **Refresh** next to the picker — SlackSucker reruns `slackdump list channels -format JSON` and `list users -format JSON`, merges them so DMs show the partner's display name, and saves the result.

The cache is refreshed automatically when:
- You launch the app and a workspace is selected but the cache is empty
- You switch workspaces via the Manage… sheet
- You switch the form into "Channel / DM" mode for the first time after launch

## Presets

Hit **Save preset…** to snapshot the current form (scope, time range, flags) under a name. Saved presets appear in the sidebar; click one to repopulate the form. Saved presets live at `~/Library/Application Support/SlackSucker/presets.json`.

## Run history

The sidebar shows the five most recent runs. Click any row to repopulate the form with that run's settings (handy for "do that again, but for a different week"). The full history (up to 50 entries) lives in `runs.json`.

## Cancel & resume

While a run is in flight, **Cancel** sends SIGTERM. If slackdump got far enough to create the SQLite checkpoint inside the run folder, a **Resume** chip appears in the live-output card; clicking it invokes `slackdump resume -o <folder>` which picks up at the checkpoint.

## Thread URL handling (the hidden workaround)

Slackdump 4.x has a quirk: when its scope argument is a Slack permalink, it correctly records the message metadata but doesn't fetch attachments — the FILE table stays empty and `__uploads/` is never created.

SlackSucker works around this transparently. When you submit a thread URL, the argv builder rewrites it from:

```
slackdump archive -o <out> https://x.slack.com/archives/C123/p1700000000123456
```

to:

```
slackdump archive -o <out> -time-from 2023-11-14T22:13:19 -time-to 2023-11-14T22:13:21 C123
```

— archiving the parent channel within a 2-second UTC window around the thread parent's timestamp. The narrow window almost always catches just the target message; slackdump's channel-archive flow follows the thread tree if there are replies.

You'll see a `[scope] Thread URL — substituting channel archive with ±1s time bracket…` line in the live log before the actual command. Your time-range form is ignored for thread scope — a thread is identified by a single TS, not a range.

## Auto-backup on launch

Every launch zips `~/Library/Application Support/SlackSucker/` into `~/Downloads/SlackSucker backup/SlackSucker-<timestamp>.zip`. Defaults:

- 14-day retention (prefix-scoped — unrelated zips you drop in the same folder are left alone)
- 5-minute debounce so debugging-session relaunches don't fill the folder
- Errors NSLogged, never thrown — the app launches even if backup fails

All of this is configurable in **Settings → BACKUP**: toggle, path picker, retention stepper, "Run backup now". The recent-backups list has **Test** (non-destructive: extracts to a temp dir and counts entries), **Restore** (clobbers the support dir; takes a safety backup first), and **Reveal in Finder**.

## Settings layout

One scrollable window:

- **Output folder** — default `~/Downloads/SlackSucker`; overridable.
- **Default archive options** — files / avatars / member-only / sort-into-categories. The values the form starts with on each launch.
- **Appearance** — Auto / Light / Dark.
- **Diagnostics** — verbose slackdump output (`-v` appended to every archive run).
- **Backup** — described above.

## Troubleshooting

- **"slackdump binary not found in app bundle"** — the build didn't bundle the helper. Rerun `./build-app.sh` from a shell where `which slackdump` resolves, or `SLACKDUMP_BIN=/path/to/slackdump ./build-app.sh`.
- **Auth expired** — open the Workspace sheet and re-run "Add workspace…" for the affected workspace, or delete + re-add it.
- **No channels in the picker** — click **Refresh** next to the picker. Make sure a workspace is selected first. Errors surface in red under the picker.
- **Run finishes with no output** — slackdump exits 0 even when its scope filter doesn't match anything. Verify the channel ID / URL and time window in the live-output card's echoed `$ slackdump archive …` invocation.
- **`Chat/<scope>.txt` is missing** — only produced for channel / DM / thread scopes. Whole-workspace runs skip it intentionally.
- **`[organize] 0 errors` but no `Photos/` directory** — your run had no file attachments (or files were disabled). The SQLite still has all the metadata.

## Where credentials live

Slack workspace credentials are stored in `~/Library/Caches/slackdump/`, encrypted with slackdump's own machine-ID-derived key. SlackSucker never reads or backs up that directory. If you want to migrate auth to another machine, follow slackdump's own transfer guide (`slackdump help transfer`).
