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
- **Options** (slackdump-side):
  - **Download files** — fetch attachments alongside messages (default on)
  - **Avatars** — fetch user profile thumbnails to `__avatars/`
  - **Member-only channels** — workspace-wide runs only; skips channels you're not in
- **Options** (post-processing — all run after slackdump exits 0, all gated on Download files being on):
  - **Sort folders** — move attachments out of slackdump's `__uploads/` into `Videos/Photos/Audio/Other/` (default on)
  - **Bake orientation** — read each photo's EXIF Orientation tag and bake the rotation into pixel data; flatten video rotation matrices via ffmpeg. Honest scope: this fixes "phone held sideways" cases reliably, but cannot detect orientation when there's no flag (e.g. screenshots, edited copies). See "Auto-rotate (the honest version)" below.
  - **Strip metadata** — remove EXIF/IPTC/XMP from photos and videos via `exiftool`. Runs AFTER bake orientation so the rotation isn't lost.
  - **Transcribe A/V** — run the `transcribe/` subproject against every audio/video file; emit `<name>.txt` next to the source. Whisper model picked in Settings.
  - **Hashes** — write `hashes.txt` at the run-folder root. Algorithms (MD5/SHA-1/SHA-256) picked in Settings; defaults to SHA-256.
- **Export folder**: above the live output, a card shows the resolved export root. The "Choose…" button picks a per-session override that doesn't persist — Settings is still the source of the default. Reset returns to that default.
- **Run / Live output**: the blue gradient button kicks off the run. Output streams into the log card; chips along the top open the SQLite database, reveal the run folder, or resume a cancelled run.

Each run writes to `~/Downloads/SlackSucker/<scope>_<YYYYMMDD_HHmmss>/`.

## Output layout

A successful run produces:

```
~/Downloads/SlackSucker/<scope>_<YYYYMMDD_HHmmss>/
├── slackdump.sqlite           Source of truth — slackdump's archive
├── archive.log                Every line slackdump streamed
├── organize-log.txt           FileOrganizer summary (file counts per category)
├── orient-log.txt             Orientation-bake summary (when toggle on)
├── metadata-log.txt           Metadata-strip summary (when toggle on)
├── transcribe-log.txt         Transcription summary (when toggle on)
├── hashes.txt                 Per-file checksums (when toggle on)
├── __avatars/                 User profile thumbnails (untouched)
├── Videos/                    .mp4 .mov .m4v .mkv .webm .avi …
│   └── <name>.txt             Whisper transcript (when Transcribe A/V on)
├── Photos/                    .jpg .jpeg .png .heic .webp .gif .svg …
├── Audio/                     .mp3 .m4a .wav .ogg .flac .opus …
│   └── <name>.txt             Whisper transcript (when Transcribe A/V on)
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

## Post-processing pipeline

When their respective toggles are on, four post-processing steps run after slackdump exits 0, in this order:

1. **Sort folders** — moves `__uploads/<FILE_ID>/<name>` into `Videos/Photos/Audio/Other/`
2. **Bake orientation** — Core Image re-encodes photos with the EXIF Orientation baked in; ffmpeg re-encodes videos with the rotation matrix flattened
3. **Strip metadata** — `exiftool -all=` over Photos/ and Videos/
4. **Transcribe A/V** — `transcribe.py -i <file> -o <name>.txt -m <model>` for every Videos/ and Audio/ file
5. **Hashes** — single-pass stream-hash with the selected algorithms; write `hashes.txt`

Then `Chat/<scope>.txt` is generated last (for channel/DM/thread scopes).

Each step is independent. If exiftool isn't installed, only "Strip metadata" reports skipped; the rest still run. Each step also writes its own `<name>-log.txt` next to the SQLite, so you can audit what happened without re-running.

### Auto-rotate (the honest version)

Bake orientation handles the **photo-rotated-because-the-phone-was-sideways** case reliably. The EXIF Orientation tag is what 90% of "rotated" photos actually contain — Core Image reads it, rotates the pixel data, then resets the tag. After this, no downstream viewer needs to honor the tag because the pixels are already correct.

What it can NOT do:

- Detect that a screenshot should be rotated (no EXIF flag = no signal).
- Detect that a photo with a flat horizon should be rotated (no metadata, content inference is required).
- Reliably detect "people-upright" via face detection — works in best-case (one large face), fails on group shots, side profiles, indoor scenes, and content with no faces.

That ML-based "look at the picture, decide which way is up" inference is genuinely hard and out of scope. If you need it, run the photos through a dedicated tool after the SlackSucker export.

### File ordering

The "Order" picker controls the `0001_, 0002_, …` prefix applied by **Sort folders**:

- **Slack message timestamp** *(recommended)* — joins `slackdump.sqlite` to read each file's parent `MESSAGE.TS`. Within a single message that has multiple attachments, files keep their `FILE.IDX` order.
- **Capture date** — EXIF `DateTimeOriginal` (photos) and QuickTime `creationDate` (videos), with `FILE.DATA.created` (Slack server upload time) as a fallback when the metadata was stripped.
- **Filename number** — extracts the first numeric run from each filename (`IMG_3079.MP4` → 3079, `01_clip.mov` → 1). Useful when the uploader manually numbered files before sending.
- **No order** — leaves original filenames untouched.

#### Posting workflow for ordered runs

**Tell the original poster to type a short caption between uploads.** Even one character of text forces iOS Slack to commit the upload-so-far as its own message before continuing — the in-flight batch is broken into N separate messages, each with its own `MESSAGE.TS`, and **Slack message timestamp** ordering produces the true post order.

```
Tap upload → "1." → send
Tap upload → "2." → send
Tap upload → "3." → send
```

That feels like one logical post to the client (a narrated reel) but is structurally five messages — exactly what the ordering query needs. Verified end-to-end against the same five clips in two configurations:

- **Five separate messages** → 0001…0005 in correct order. ✓
- **One conceptual post, interleaved with text** → Slack wraps the five uploads as a thread; thread reply TSs land in correct order. 0001…0005 in correct order. ✓
- **One Slack message, five attachments in the picker** → Slack discards selection order; SlackSucker emits `[organize] ⚠ batched message(s)` and the within-batch order is **not** real post order. ✗

#### The unfixable case: batched iOS uploads

When somebody in your Slack opens the iOS app, multi-selects N files in the Photos picker, and posts them as one message without typing anything between:

1. iOS Slack re-encodes the videos client-side before upload, stamping all N files with identical QuickTime `CreateDate` / `TrackCreateDate` / `MediaCreateDate`. The originals' camera-shutter timestamps are lost at this step.
2. The N files are uploaded **in parallel**. Whichever finishes first (typically the smallest file) gets the lowest `FILE.DATA.created` timestamp — so `created` reflects upload-completion order, not selection order.
3. All N files share a single `MESSAGE.TS`, so the **Slack message timestamp** prefix can't disambiguate within the batch.
4. Slack's `files[]` array order in the message JSON is **not documented to match user selection order** — no `index`, `sequence`, or `batch_id` field exists anywhere in the Slack file/message API.

For batch-uploaded videos with random/GUID filenames (the iOS Photos default), there is **no signal in the archive** that captures the order they were posted in. Not in Slack's data, not in the file metadata, not in the URL. SlackSucker detects this and prints:

```
[organize] ⚠ N file(s) across M batched message(s) — Slack does not record selection order for files posted together. Confirm order with the original poster before editing.
```

**Workarounds** when you're stuck with an existing batched archive, in order of reliability:

1. **Numeric filenames** — if the poster prefixed files (`01_intro.mov`, `02_b-roll.mov`, …) before sending, Slack preserves the `name` field even when it strips other metadata. Switch to **Filename number** ordering.
2. **Order list in a follow-up message** — have the poster send a text message right after the batch listing the intended order. SlackSucker doesn't parse this automatically; treat it as documentation for whoever does the edit.

If neither applies, the order is not recoverable. Catch it before the edit, not after — and **set the posting workflow expectation up front**: "type a brief note between clips."

### Hash manifest format

`hashes.txt` is GNU coreutils-compatible — you can verify it with:

```sh
cd <run-folder>
# pull just the SHA-256 section out and pipe to sha256sum -c
awk '/^# SHA-256/{f=1;next}/^# /{f=0}f' hashes.txt | sha256sum -c -
```

Each section is preceded by `# <ALGO>`; lines below it are `<hex>  <relative-path>`.

### Transcription setup

The Transcribe A/V toggle requires the `transcribe/` PhantomLives subproject. Resolution order:

1. `$SLACKSUCKER_TRANSCRIBE_BIN` env var (escape hatch)
2. `transcribe` on PATH (if you symlinked the script)
3. `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py` (the sibling checkout)

If none of those exist, the live log shows `[transcribe] skipped — no transcribe binary found` and the run continues. Apple Silicon only — `transcribe.py` uses MLX-accelerated Whisper.

## Auto-backup on launch

Every launch zips `~/Library/Application Support/SlackSucker/` into `~/Downloads/SlackSucker backup/SlackSucker-<timestamp>.zip`. Defaults:

- 14-day retention (prefix-scoped — unrelated zips you drop in the same folder are left alone)
- 5-minute debounce so debugging-session relaunches don't fill the folder
- Errors NSLogged, never thrown — the app launches even if backup fails

All of this is configurable in **Settings → BACKUP**: toggle, path picker, retention stepper, "Run backup now". The recent-backups list has **Test** (non-destructive: extracts to a temp dir and counts entries), **Restore** (clobbers the support dir; takes a safety backup first), and **Reveal in Finder**.

## Settings layout

One scrollable window:

- **Output folder** — persistent default. `~/Downloads/SlackSucker` if unset. The main-screen "Choose…" is a per-session override that doesn't write here; this is the source of truth that survives relaunch.
- **Default archive options** — files / avatars / member-only / sort-into-categories. The values the form starts with on each launch.
- **Post-processing defaults** — bake orientation / strip metadata / transcribe + Whisper model / hashes + algorithms. The main-screen toggles default to these on launch.
- **Appearance** — Auto / Light / Dark.
- **Diagnostics** — verbose slackdump output (`-v` appended to every archive run).
- **Backup** — described above. The top-level row also has **Reveal folder**, **Verify latest**, and **Restore latest…** convenience buttons; per-row chips are still available on each individual backup.

## Troubleshooting

- **"slackdump binary not found in app bundle"** — the build didn't bundle the helper. Rerun `./build-app.sh` from a shell where `which slackdump` resolves, or `SLACKDUMP_BIN=/path/to/slackdump ./build-app.sh`.
- **Auth expired** — open the Workspace sheet and re-run "Add workspace…" for the affected workspace, or delete + re-add it.
- **No channels in the picker** — click **Refresh** next to the picker. Make sure a workspace is selected first. Errors surface in red under the picker.
- **Run finishes with no output** — slackdump exits 0 even when its scope filter doesn't match anything. Verify the channel ID / URL and time window in the live-output card's echoed `$ slackdump archive …` invocation.
- **`Chat/<scope>.txt` is missing** — only produced for channel / DM / thread scopes. Whole-workspace runs skip it intentionally.
- **`[organize] 0 errors` but no `Photos/` directory** — your run had no file attachments (or files were disabled). The SQLite still has all the metadata.

## Where credentials live

Slack workspace credentials are stored in `~/Library/Caches/slackdump/`, encrypted with slackdump's own machine-ID-derived key. SlackSucker never reads or backs up that directory. If you want to migrate auth to another machine, follow slackdump's own transfer guide (`slackdump help transfer`).
