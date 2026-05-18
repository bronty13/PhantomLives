# PurpleReel Integration Test Plan

End-to-end scenarios that exercise the parts of the app the XCTest
suite can't reach: real video files, real FCP, real SFTP servers,
real Whisper / Ollama / ffmpeg invocations, real keyboard-driven
playback. Run through this on every release candidate or after any
material change to the player / transcode / backup / delivery
pipelines.

**Conventions:**
- Each scenario has **Setup**, **Steps**, and **Pass criteria**.
- "**App**" means `/Applications/PurpleReel.app`.
- "**The folder**" is whichever test media folder you've chosen (see
  Scenario 0 — Setup).
- Where outputs land:
  - Transcodes: `~/Downloads/PurpleReel/transcoded/`
  - FCPXML: `~/Downloads/PurpleReel/exports/`
  - MHL backups: each destination's root
  - Auto-backups: `~/Downloads/PurpleReel backup/`
  - Thumbnail cache: `~/Library/Application Support/PurpleReel/thumbnails/`
- After each destructive scenario, run `Window → Reset Window State…`
  if the UI gets stuck.

Track results inline by editing the **Result** lines (`[ ]` → `[✓]`
or `[✗] notes`).

---

## Scenario 0 — Test material setup

**Setup:**
- Create `~/PurpleReel-Tests/` with at least:
  - 3+ different camera-original `.mov` or `.mp4` clips of varied
    duration (≥10 s, ≥1 min, ≥5 min recommended for the transcode
    scenarios)
  - 1+ clip at 29.97 fps (NTSC) and 1+ at 23.976 fps so the
    FCPXML test exercises both rationals
  - 1+ clip with clear dialog (for Whisper) — a podcast extract or
    interview clip works well
  - 2+ visually-similar takes of the same shot (for the similar-takes
    test)
- One Adobe `.cube` LUT file (Rec.709-to-sRGB or a vendor look)
- An Ollama instance running locally with at least one model pulled
  (e.g. `ollama pull llama3.2:1b`)
- A real SFTP server you have credentials for (a localhost test
  server is fine — see Scenario 8 for setup)
- Final Cut Pro installed at `/Applications/Final Cut Pro.app`

**Steps:**
1. Fresh-install via `./build-app.sh && ./install.sh`.
2. Quit any prior copy first; verify `/Applications/PurpleReel.app`
   was replaced.
3. Launch from Spotlight.

**Pass criteria:**
- App opens to the empty-state ("Choose a folder of source media").
- Sidebar is exactly 240 px wide (no narrow strip, no wrong layout).
- Toolbar shows 9 items: Toggle Sidebar, Open Folder, Rescan, AI,
  Batch Rename, SFTP, Verified Backup, Transcode, Send to FCP.

**Result:** [ ]

---

## Scenario 1 — Library scan + thumbnail strip

**Steps:**
1. Toolbar → **Open Folder…** → pick `~/PurpleReel-Tests/`.
2. Wait for the scanning indicator to clear.
3. In the asset table, hover the cursor over the **leftmost
   thumbnail column** of one row. Slowly drag horizontally across the
   thumbnail.
4. Move the cursor away from the thumbnail.

**Pass criteria:**
- Sidebar's "Items" count matches the file count in
  `find ~/PurpleReel-Tests -type f \( -name "*.mov" -o -name "*.mp4" \)`.
- Each row shows codec / resolution / fps / duration / size populated
  from AVFoundation metadata (not "—").
- On hover, the thumbnail cycles smoothly through ~12 frames as the
  cursor moves L→R. A small tick row appears at the bottom of the
  cell indicating the active frame index.
- On hover exit, the cell returns to the middle frame.
- First hover may show a brief film-icon placeholder while the
  thumbnail strip generates; second hover on the same row is
  instant (cache hit).

**Result:** [ ]

---

## Scenario 2 — Player transport + waveform + LUT

**Setup:** any clip with audio.

**Steps:**
1. Click a clip in the table. Detail pane appears below.
2. Wait ~1 s for the waveform to render under the scrubber.
3. Press **Space** to play. Press again to pause.
4. Press **L** repeatedly. Then **J** repeatedly. Then **K**.
5. Hold **→** for a few seconds. Then **←**.
6. Click somewhere in the middle of the scrubber.
7. With playback paused, press **I**, scrub forward a few seconds,
   press **O**.
8. Click **Load LUT…** below the transport. Pick your test `.cube`
   file.
9. Click **×** next to the LUT name to clear it.

**Pass criteria:**
- Audio waveform renders as a vertically-mirrored peak band behind
  the scrubber.
- Space toggles play/pause. The play button icon swaps.
- L cycles +1× → +2× → +4× (audio pitches up). J does the same in
  reverse. K stops.
- Arrow keys step exactly 1 frame at a time (TC readout advances by
  1 frame each press).
- Click-to-seek lands the playhead at the clicked X position;
  TC readout updates.
- I and O paint a translucent purple range overlay on the scrubber
  between the two timecodes.
- Loading the LUT immediately changes the video's color grade. The
  LUT bar shows the LUT's name + cube size (e.g. `My Look (33³)`).
- Clearing the LUT reverts to neutral.

**Result:** [ ]

---

## Scenario 3 — Logging round-trip (markers / subclips / tags / rating)

**Setup:** clip from Scenario 2 still selected.

**Steps:**
1. Press **M** at several points during playback.
2. Set I/O markers (I, then play forward, then O). Press **S** to
   save the subclip.
3. In the **Tags** field, type `interview`, press Return. Then
   `selects`, Return.
4. Click 5 stars in the **Rating** row.
5. Type a paragraph into the **Description** text area.
6. Quit PurpleReel (⌘Q).
7. Relaunch.
8. Click the same clip.

**Pass criteria:**
- Each marker appears in the **Markers** list with the timecode
  at which it was created. Clicking a TC jumps the playhead.
- The subclip appears in **Subclips** with name like
  `<filename> [00:00:01:00]`. Clicking either TC jumps.
- Tag chips appear with × to remove.
- Stars stay yellow at the chosen rank.
- Description text persists in the text area.
- **After relaunch:** every marker, subclip, tag, rating, and the
  description survives. The transcript section (if any) also survives.

**Result:** [ ]

---

## Scenario 4 — Native transcode (AVFoundation presets)

**Setup:** clip from Scenario 1, ≥10 s.

**Steps:**
1. With the clip selected, toolbar → **Transcode** → **ProRes
   Proxy**. Queue sheet opens.
2. Wait for completion.
3. Click **Reveal** on the completed row.
4. Open the output file in QuickTime Player. Play.
5. From a Terminal, run `ffprobe -hide_banner <output-path>` (or
   `mediainfo`) on the result.

**Pass criteria:**
- Queue sheet shows the job under **Running** with a progress bar
  reaching 100 %, then under **Completed**.
- Output lands in `~/Downloads/PurpleReel/transcoded/<base>_proxy.mov`
  with no collision suffix (or `_1.mov`, etc., if you re-ran).
- QuickTime plays the result without warnings.
- `ffprobe` confirms codec is ProRes (`Apple ProRes 422 (Standard)` or
  similar) and the container is QuickTime/MOV.
- Audio is preserved.

Repeat with **H.264 1080p**, **HEVC 1080p**, and **Pass-through
(rewrap)** to round-trip the three primary AVFoundation paths.

**Result:** ProRes Proxy [ ] · H.264 1080p [ ] · HEVC 1080p [ ] ·
Pass-through [ ]

---

## Scenario 5 — ffmpeg Phase-2 presets (DNxHR / Cineform / MXF)

**Setup:** `ffmpeg` installed (`which ffmpeg` returns a path). Same
clip as Scenario 4.

**Steps:**
1. Toolbar → **Transcode** → **DNxHR SQ (1080p, ffmpeg)**.
2. Wait for completion.
3. Verify with `ffprobe`.
4. Repeat for **DNxHR HQ**, **Cineform**, **ProRes in MXF**.
5. Temporarily move `ffmpeg` out of `PATH` (e.g.
   `sudo mv /opt/homebrew/bin/ffmpeg /opt/homebrew/bin/ffmpeg.bak`)
   and retry one of the presets.
6. Restore `ffmpeg`.

**Pass criteria:**
- Each preset produces a file with the correct codec/container per
  `ffprobe` (`dnxhd`/`dnxhr_sq` etc., `cfhd` for Cineform,
  `prores_ks` inside `mxf`).
- Progress bar advances smoothly while ffmpeg encodes (the
  `time=HH:MM:SS.xx` parser is feeding the UI).
- With ffmpeg missing, the job fails fast with a clear error
  message like `ffmpeg not found. Install with brew install
  ffmpeg`.

**Result:** DNxHR SQ [ ] · DNxHR HQ [ ] · Cineform [ ] · MXF [ ] ·
Missing-ffmpeg error [ ]

---

## Scenario 6 — Verified backup + MHL

**Setup:**
- A test source folder: `mkdir -p /tmp/pr-back-src && cp ~/PurpleReel-Tests/*.mov /tmp/pr-back-src/`
- Two empty destinations on different volumes if possible:
  `/tmp/pr-back-dst1` and `/tmp/pr-back-dst2`

**Steps:**
1. Toolbar → **Verified Backup**.
2. Source → `/tmp/pr-back-src`. Add both destinations. Algorithm:
   SHA-1.
3. Click **Start Backup**.
4. Wait for completion.
5. In Terminal, for each source file run
   `shasum <source-path>` and compare against the value in each
   destination's `.mhl`.
6. Run `xmllint --noout <destination>/<source>_<stamp>.mhl`.
7. Tamper test: corrupt one source file mid-batch by appending a
   byte (`echo x >> /tmp/pr-back-src/<file>`). Re-run the backup.

**Pass criteria:**
- Each file goes through the per-row states queued → hashing →
  copying → verifying → done.
- Both destinations receive byte-identical copies (`diff -r
  /tmp/pr-back-src /tmp/pr-back-dst1`).
- Each destination has a `<source-name>_<timestamp>.mhl` at its
  root.
- `xmllint --noout` reports no errors on the MHL files.
- Hashes inside each `.mhl` match `shasum` output for the
  corresponding source files.
- With ≥2 destinations the per-file copy-and-verify phase runs in
  parallel (overall wall time ≈ slowest destination, not sum).
- Tamper test: when re-run after corrupting the source, the affected
  row fails with a clear message and the MHL excludes that file.

**Result:** clean backup [ ] · MHL parses [ ] · hashes match
shasum [ ] · parallel observed [ ] · tamper test [ ]

---

## Scenario 7 — FCPXML export + Final Cut Pro round-trip

**Setup:** Final Cut Pro installed and open with a library available
for import. The clip from Scenario 3 (with markers / subclips /
tags / 5-star rating).

**Steps:**
1. Toolbar → **Send to FCP** → **Selected Clip to Final Cut Pro**.
2. FCP should launch (or come forward) and prompt for an event /
   library to import into.
3. Pick an event. Confirm import.
4. In FCP's browser, select the imported clip.
5. Open the **Inspector** → **Info** tab and **Metadata** view.
6. Check the **Tags** lane and clip's **Favorite** marker.
7. Open the clip in the Viewer; check **Markers** panel
   (View → Show in Viewer → Markers).
8. Export the same library or a single clip → **Entire Library
   to Final Cut Pro**.
9. Quickly: edit the exported `.fcpxml` in
   `~/Downloads/PurpleReel/exports/` open in a text editor; confirm
   asset-clip + format + marker + keyword + rating elements present.

**Pass criteria:**
- FCP opens automatically (no Finder fallback).
- Import completes without warnings.
- Clip lands in the chosen event with the original file as
  source-of-truth (no relink prompt).
- Markers appear on the timeline at the correct timecodes with the
  original notes.
- The clip range bracketed by the I/O subclip imports as a separate
  asset-clip / Compound Clip range with the correct in/out.
- Tags appear as Keywords in the inspector.
- 5-star rating shows as a Favorite range in FCP's selection
  inspector.
- Library export covers every catalogued asset.
- `xmllint --noout` on the exported `.fcpxml` returns 0.
- No `&` characters appear unescaped in the XML (paths with `&` are
  written as `&amp;` per the test that caught the original bug).

**Result:** import opens FCP [ ] · markers land [ ] · subclips
land [ ] · tags as keywords [ ] · 5-star → Favorite [ ] · library
export [ ] · xmllint clean [ ]

---

## Scenario 8 — SFTP delivery (SSH key)

**Setup:** an SSH host you can write to via key auth. For a
localhost test:

```sh
# enable Remote Login in System Settings → General → Sharing.
ssh-keygen -t ed25519 -f ~/.ssh/purplereel_test -N ""
cat ~/.ssh/purplereel_test.pub >> ~/.ssh/authorized_keys
mkdir -p /tmp/pr-sftp-target
```

**Steps:**
1. Toolbar → **SFTP Delivery** → **New**.
2. Fill: Host `localhost`, Port `22`, User `$(whoami)`, Remote
   Path `/tmp/pr-sftp-target`, Identity file
   `~/.ssh/purplereel_test`, **Accept new host keys** checked.
   **Save Destination**.
3. **Add Files…** → pick 2-3 clips from `~/PurpleReel-Tests/`.
4. **Start Upload**.
5. Watch the per-file progress.
6. When done, in Terminal: `ls -la /tmp/pr-sftp-target/` and
   `shasum /tmp/pr-sftp-target/* ~/PurpleReel-Tests/*` to compare.
7. Expand **Raw sftp log** in the sheet.

**Pass criteria:**
- Connection succeeds without a password prompt (key auth).
- Each file shows progress climbing in percentage steps as sftp
  emits `100%` lines.
- All files land at the destination, byte-identical to source
  (matching shasum).
- Raw log shows `Uploading … to …` and the percentage lines for each
  file.
- Re-running the same job overwrites cleanly (sftp's `put`
  overwrites; no error).

**Result:** [ ]

---

## Scenario 9 — SFTP delivery (password auth via sshpass)

**Setup:** same as Scenario 8 but the test server must accept
password auth. Install sshpass:
`brew install hudochenkov/sshpass/sshpass`. If your localhost
doesn't accept passwords for `ssh`, set up a Docker-based test
server or use a real one.

**Steps:**
1. Open the destination from Scenario 8 in the editor (or **New**).
2. Type a password into the **Password** secure field.
3. Confirm the green "sshpass detected — password auth ready"
   status. Save.
4. **Start Upload** on a fresh batch of files.
5. Run `security find-generic-password -s
   com.bronty13.PurpleReel.sftp -a <destination-uuid>` in Terminal
   (UUID visible in the destination's JSON under
   `~/Library/Preferences/com.bronty13.PurpleReel.plist`).

**Pass criteria:**
- Upload proceeds without prompting for a password.
- `security find-generic-password` confirms the password is in the
  Keychain under the right service + account.
- `ps -A` during the upload does NOT show the password on the
  command line (sshpass receives it via `SSHPASS` env, not `-p`).
- Clearing the password in the editor and saving removes the
  Keychain entry (`security find-generic-password … -a <uuid>`
  returns "could not be found").

**Result:** upload via password [ ] · Keychain stores it [ ] · not
in ps [ ] · clear deletes [ ]

---

## Scenario 10 — Whisper transcription + auto-markers

**Setup:** sibling `transcribe/transcribe.py` present at the
default path (or override in **Settings → AI**). Python 3.10+ on
PATH. First run will pull ~1 GB of MLX-Whisper weights — let it
complete. A clip with clear dialog from Scenario 0.

**Steps:**
1. Open **Settings** (⌘,) → **AI** tab.
2. Confirm green ✓ next to "transcribe.py found".
3. Pick the **turbo** model.
4. Close Settings. Select the dialog clip.
5. Toolbar → **AI** → **Transcribe + Create Markers**.
6. Watch the AI sheet; transcription runs locally.
7. When done, dismiss the sheet.
8. Inspect the **Markers** list and click TCs to jump.
9. Quit and relaunch the app; re-select the clip.

**Pass criteria:**
- During the run, the sheet shows progress ("Transcribing … with
  MLX Whisper…").
- On completion the sheet flips to **Transcript saved** with the
  segment count, model name, and each segment listed.
- The **Markers** list now contains one entry per segment, with the
  transcribed text as the note and an accurate timecode-in.
- **After relaunch**, the transcript persists (re-selecting the
  clip restores all markers; no need to re-run Whisper).
- Switching the model to `tiny` and re-running on a short clip
  completes in seconds.

**Result:** [ ]

---

## Scenario 11 — Ollama auto-describe

**Setup:** Ollama running (`ollama serve` or the menu-bar app), at
least one model pulled.

**Steps:**
1. **Settings → AI**. Confirm green ✓ next to "Ollama is running
   at localhost:11434". The Model picker shows your installed
   models. Pick one.
2. Close Settings.
3. Pick a clip that already has a transcript from Scenario 10.
4. Toolbar → **AI** → **Auto-Describe (Ollama)**.
5. Wait for the sheet to show **Description saved**.
6. Close the sheet and check the **Description** field on the
   detail pane.
7. Stop Ollama (`ollama serve` Ctrl-C or quit the menu-bar app).
8. Open Settings → AI. Try Auto-Describe again.

**Pass criteria:**
- With Ollama running, the LLM returns a coherent 1–2 sentence
  description referencing the filename and (if transcript
  available) dialog content.
- The description writes to the clip's metadata field and persists
  across relaunches.
- With Ollama stopped, the AI sheet shows a clear error (`Ollama
  isn't responding at http://localhost:11434…`) instead of hanging.

**Result:** describe succeeds [ ] · description persists [ ] ·
ollama-down error [ ]

---

## Scenario 12 — Similar takes (BK-tree clustering)

**Setup:** at least 2 visually-similar takes of the same shot in
the loaded library.

**Steps:**
1. Toolbar → **AI** → **Find Similar Takes**.
2. Watch the progress bar as middle frames are hashed.
3. On completion, examine each cluster card.
4. Note the "best" pick rationale ("Highest rated (n★)…" or
   "Longest take…").

**Pass criteria:**
- Hashing finishes; sheet shows the cluster count.
- Each cluster lists 2+ assets with one starred as best.
- The rationale matches the data: a 5-star clip in the cluster wins
  even if it's shorter; otherwise the longest take wins.
- Clips with obviously different content do NOT appear in the same
  cluster.

**Result:** [ ]

---

## Scenario 13 — Batch rename

**Setup:** at least 3 clips in the catalog.

**Steps:**
1. Toolbar → **Batch Rename**.
2. Scope: **All catalogued**.
3. Template: `{date}_{orig}_{counter:04}{ext}`.
4. Preview rows render — check each new name is correct.
5. Force a conflict: set template to `same{ext}` and confirm the
   second-onwards rows go red.
6. Restore the template. Click **Rename N clips**.
7. Examine the table.
8. Verify on disk: `ls -la ~/PurpleReel-Tests/`.

**Pass criteria:**
- Preview shows the original → proposed name pairs with arrows.
- Conflicts are flagged with a red warning icon; the **Rename**
  button count drops by the conflict count.
- Apply renames the files on disk AND updates the catalog (table
  rows show new names, not old).
- Markers/tags/ratings/subclips/transcripts on the renamed clips
  are still attached after the rename (foreign keys cascade
  correctly since rename is an UPDATE, not DELETE+INSERT).

**Result:** preview correct [ ] · conflicts flagged [ ] · disk
renamed [ ] · catalog updated [ ] · logging survives [ ]

---

## Scenario 14 — Auto-backup on launch + restore

**Setup:** at least one clip with logging from Scenario 3 in the DB.

**Steps:**
1. Confirm `~/Downloads/PurpleReel backup/` exists and contains the
   most recent zip.
2. Quit PurpleReel. Wait > 5 minutes (defeat the debounce). Or set
   `defaults delete com.bronty13.PurpleReel lastBackupAt`.
3. Relaunch. A new auto-backup should be written.
4. Inspect the zip:
   `unzip -l ~/Downloads/PurpleReel\ backup/PurpleReel-*.zip`.
5. Simulate corruption: quit the app and
   `rm -rf ~/Library/Application\ Support/PurpleReel/`. Relaunch.
   The DB is empty.
6. Unzip the most recent backup back into Application Support:
   `unzip -o ~/Downloads/PurpleReel\ backup/PurpleReel-*.zip -d ~/Library/Application\ Support/`.
7. Quit + relaunch.

**Pass criteria:**
- Each cold launch (with debounce defeated) produces a new
  `PurpleReel-<timestamp>.zip`.
- The zip contains `PurpleReel/purplereel.sqlite` (plus thumbnails
  if any).
- Retention trim keeps backups within `backupRetentionDays`
  (default 14); older zips with the right prefix are deleted; zips
  with other prefixes are untouched.
- After restore from a zip, the catalog (clips + logging) is
  recovered.

**Result:** [ ]

---

## Scenario 15 — Window-state recovery

**Setup:** clean state.

**Steps:**
1. Open the app. Note the sidebar width and window position.
2. Quit. In Terminal, inject a poisoned split-view frame:
   `defaults write com.bronty13.PurpleReel "NSSplitView Subview Frames TestSplit-1" '("0.0, 0.0, 50.0, 800.0, NO, NO")'`
3. Relaunch.
4. Now use **Window → Reset Window State…** → confirm.
5. Quit and relaunch.

**Pass criteria:**
- Even with the injected poisoned value, the sidebar still renders
  at the canonical 240 px (the manual `HStack` ignores
  `NSSplitView` state for the top-level chrome — that's the
  fundamental MusicJournal-pattern guarantee).
- The `NSSplitView Subview Frames *` keys are wiped on launch (per
  `WindowStateGuard.preflightPurgeSplitViewFrames`).
- "Reset Window State…" wipes the window position and `.savedState`
  directory; next launch starts from default geometry.

**Result:** sidebar stable [ ] · preflight wipes [ ] · menu reset
works [ ]

---

## Scenario 16 — Cold-start sanity

**Setup:** Quit PurpleReel. Delete every cache + DB:
```sh
rm -rf ~/Library/Application\ Support/PurpleReel
rm -rf ~/Downloads/PurpleReel
rm -rf ~/Downloads/PurpleReel\ backup
defaults delete com.bronty13.PurpleReel 2>/dev/null
```

**Steps:**
1. Launch. App should open to empty state.
2. **Open Folder…** the test folder.
3. Confirm the catalog DB at
   `~/Library/Application Support/PurpleReel/purplereel.sqlite` was
   created by the v1 migration.
4. Confirm the auto-backup zip is created on launch.

**Pass criteria:**
- No errors in Console.app's PurpleReel logs.
- DB file exists, opens in `sqlite3 …` cleanly, `.tables` shows
  asset / tag / asset_tag / marker / subclip / rating / transcript /
  asset_fts.
- Auto-backup zip is non-empty and parsable.

**Result:** [ ]

---

## Scenario 17 — Release-build performance smoke

**Setup:** a folder with 500+ clips if available (otherwise dial
expectations).

**Steps:**
1. `./build-app.sh` (Release config is the default).
2. Time the first scan with `time …` or a stopwatch.
3. Scroll through the table rapidly.
4. Hover-scrub a few rows.
5. Open Activity Monitor → keep PurpleReel selected.

**Pass criteria:**
- Initial scan completes in a reasonable time for the file count
  (rough rule: ≤2× the time `find` takes to enumerate the same
  folder).
- Scrolling is smooth — no visible chop, no spinner flicker. (UI
  thread should stay under ~5 % CPU in idle scroll.)
- Hover-scrub on the first hover renders the strip within ~1 s;
  subsequent hovers are immediate.
- Memory growth is bounded: opening + scanning + scrubbing 100 rows
  shouldn't push the app past ~500 MB resident.

**Result:** scan time acceptable [ ] · scroll smooth [ ] · hover
responsive [ ] · memory bounded [ ]

---

## Scenario 18 — Multi-select + categorized Convert + Convert dialog + per-asset progress

Covers the Kyno-parity Convert workflow shipped on top of the original
transcode scenario: multi-selection in the grid + list, the categorized
right-click Convert submenu (with Recently Used), the "Convert & Transcode
Media" pre-queue dialog, and the per-asset transcode-progress overlays on
the grid tiles.

**Setup**
- Workspace contains at least three short video clips (≤ 30 s each is
  enough for the progress overlay to be observable).
- No prior Convert run for these files: `~/Downloads/PurpleReel/transcoded/`
  is empty (or the user is OK with the "Skip items that already exist
  on target" behaviour kicking in).

**Steps**

1. **Multi-select in grid** — switch to Grid view (⌘1). Click the first
   clip. Cmd-click two more clips. Then Shift-click a clip further down
   to extend the range.
   - **Expected:** Each clicked clip shows a selection ring; the most
     recently clicked clip shows a thicker (primary) ring. The selection
     count matches what was clicked.
2. **Multi-select in list** — switch to List view (⌘2). Click a row,
   Cmd-click two more rows, Shift-click a fourth.
   - **Expected:** Standard macOS Table multi-row selection. Selection
     persists when switching back to Grid (⌘1).
3. **Right-click on a non-selected row** — in either view, right-click
   a clip that isn't in the current selection.
   - **Expected:** The selection collapses to just that row before the
     menu's batch actions run; the user sees only that one clip in the
     subsequent Convert dialog.
4. **Convert submenu — Recently Used** — on a brand-new install (no
   MRU yet), open the Convert submenu.
   - **Expected:** No "Recently Used" group. Categories show: Editing
     (ProRes 422), Web (H.264 1080p/720p, HEVC), Proxies (ProRes
     Proxy), Rewrap (Pass-through), DNxHR (SQ/HQ), Distribution
     (Cineform, ProRes-in-MXF). Categories with no presets are not
     rendered.
5. **Pick a preset → dialog opens** — right-click a multi-selection,
   Convert → Web → "H.264 1080p".
   - **Expected:** Convert & Transcode Media sheet appears. Shows:
     destination directory (default `~/Downloads/PurpleReel/transcoded`),
     "Select…" button, two toggles (Keep folder structure, Skip
     existing), preset summary (File format MP4, Category Web, Engine
     AVFoundation, suffix `_h264_1080p`), and the summary line
     "N files will be created in <path>".
6. **Change destination via Select…** — click Select… and pick a folder
   (e.g. `~/Desktop/test-out/`).
   - **Expected:** Text field updates to the new path; summary line
     reflects it.
7. **Keep folder structure on** — toggle on. Pick clips that span two
   different subfolders.
   - **Expected:** After Start (next step), output files end up under
     `<destination>/<relative subfolder>/` instead of all flat at
     destination root. Verify with Finder.
8. **Skip existing** — leave on. Re-run the same Convert on the same
   selection.
   - **Expected:** Second run produces zero new files (existing files
     are skipped); the queue view shows no enqueued jobs from the
     second invocation. Toggle Skip off and re-run; jobs are enqueued
     with numeric suffixes (e.g. `_h264_1080p_1.mp4`).
9. **Start enqueues + queue opens** — click Start with skip off.
   - **Expected:** Sheet closes; transcode queue sheet opens
     automatically; all N jobs visible there as "queued"; first one
     transitions to "running".
10. **Per-asset progress overlay** — return to the Grid behind the
    queue sheet (close it if necessary; the queue persists).
    - **Expected:** Active clip's tile has a dark bar at the bottom
      with the preset name and an orange progress bar; percentage
      updates in real time. Queued clips have a "Queued · H.264
      1080p" label without a progress bar.
11. **Finish indicators** — wait for at least one job to finish.
    - **Expected:** A green checkmark badge in the top-right corner of
      the finished clip's tile. Bottom progress bar gone. If a job
      fails (e.g. preset incompatible with source), red X badge
      instead.
12. **Recently Used after a run** — pick a different preset for one
    more clip (Convert → Editing → ProRes 422). Then right-click any
    clip again.
    - **Expected:** "Recently Used" section appears at the top of the
      Convert menu, showing **ProRes 422** first (last pick), then
      **H.264 1080p**. ⌘E is bound to the topmost (ProRes 422).
13. **Sticky preferences across relaunches** — close PurpleReel,
    relaunch. Trigger Convert again.
    - **Expected:** The dialog remembers the destination directory,
      the Keep-folder-structure state, and the Skip-existing state
      from the previous run. Recently Used list also persists.

**Pass criteria**
- Multi-select works in both Grid and List with Cmd / Shift modifiers.
- Right-click on a non-selected row replaces the selection.
- Convert submenu shows categories + Recently Used; ⌘E hits the most
  recent preset.
- Convert dialog enforces destination + flags + skip logic correctly.
- Each grid tile shows its own progress overlay while running and the
  finish badge once done.
- Sticky destination / toggles / MRU survive relaunch.

---

## Scenario 19 — Kyno log-field metadata (Title / Description / Reel / Scene / Shot / Take / Angle / Camera)

Covers the v2 schema migration, the new Metadata tab in the inspector,
the inline-edit-on-Return UX, and the FCPXML round-trip carrying the
new fields into Final Cut Pro as `<md>` entries.

**Setup**
- Workspace contains at least one video clip with non-trivial duration.
- Final Cut Pro 11+ installed (only required for the round-trip step).

**Steps**

1. **Migration on first launch** — quit PurpleReel. Move the existing
   DB aside: `mv ~/Library/Application\ Support/PurpleReel/purplereel.sqlite ~/Desktop/`.
   Re-launch.
   - **Expected:** App starts cleanly, scans the workspace, and the
     new `clip_metadata` table is created on first migration run. No
     error in Console.
   - **Then** restore your DB: quit, move it back, relaunch.
2. **Verify migration applied to existing DB** — open Terminal:
   `sqlite3 ~/Library/Application\ Support/PurpleReel/purplereel.sqlite ".schema clip_metadata"`.
   - **Expected:** Table definition is printed with columns
     `assetId, title, description, reel, scene, shot, take, angle, camera`.
3. **Metadata tab visible in inspector** — select a clip in List view
   (⌘2). Look at the right-side inspector tab bar.
   - **Expected:** "Metadata" tab is present, left of Content / Tracks
     / Log. Selecting it shows: Rating row (5 stars + clear), Title
     field, Description multi-line, then a 6-row grid of Reel /
     Scene / Shot / Take / Angle / Camera, then a Tags section.
4. **Inline edit + persistence** — type into Title, press Return. Type
   into Description, click elsewhere. Fill in Reel "A001", Scene "1",
   Shot "A", Take "3".
   - **Expected:** Every edit commits when you press Return or move
     focus. Switch to another clip, then back — the values reload
     correctly. Quit + relaunch the app — values still there.
5. **Rating + tags from Metadata pane** — set rating to 4. Add tag
   "interior".
   - **Expected:** Stars fill yellow up to position 4. The tag
     appears as a removable pill. Click the X to remove and confirm
     it goes away (same backing table as the Log tab — they should
     stay in sync).
6. **Inline detail view shows Metadata pane** — switch to Detail view
   (⌘3). The right-side pane title says "Metadata".
   - **Expected:** Same Title / Description / Reel / Scene / Shot /
     Take / Angle / Camera form, edits commit identically.
7. **FCPXML round-trip — single clip** — pick the clip with the
   metadata you set. Send to FCP via the toolbar's "Send to FCP →
   Selected Clip to Final Cut Pro".
   - **Expected:** Final Cut Pro launches, an event is created, the
     clip imports.
   - **In Final Cut Pro**, select the imported clip and open the Info
     inspector → Metadata View → "General" or "Custom" (depending on
     FCP version). The Title / Description / Reel / Scene / Shot /
     Take / Angle / Camera fields should be populated from the
     PurpleReel sheet.
   - **Also verify** the fcpxml on disk: `cat ~/Downloads/PurpleReel/exports/PurpleReel_*.fcpxml | grep -A1 metadata`
     should show `<md key="Title" value="…"/>` style entries.
8. **FCPXML — empty metadata is skipped** — pick a clip with NO log
   fields set. Send to FCP.
   - **Expected:** Generated `.fcpxml` for that clip has NO
     `<metadata>` block (XML stays tidy when nothing is populated).
9. **Library-wide export carries metadata** — toolbar → "Send to FCP
   → Entire Library — Save .fcpxml Only".
   - **Expected:** The single bulk `.fcpxml` file contains a
     `<metadata>` block under every `<asset-clip>` whose backing
     clip has any populated log field.
10. **Tab persistence** — switch the inspector to "Metadata", then to
    "Content", then quit. Relaunch.
    - **Expected:** The Metadata tab is remembered as the active
      inspector tab (`detailTab` @AppStorage). Was "Log" the
      default; new installs land on "Content" — verify that.

**Pass criteria**
- v2 migration creates `clip_metadata` cleanly on fresh and existing
  installs.
- Metadata tab edits persist across selection changes and relaunches.
- Rating / Tags from the Metadata pane share state with the Log pane.
- FCPXML carries Title / Description / Reel / Scene / Shot / Take /
  Angle / Camera as `<md>` entries; empty fields are omitted.
- Final Cut Pro shows the fields after import.

---

## Scenario 20 — Extra List columns + sort direction + player shortcuts

Covers the optional columns toolbar control, the new sort
ascending/descending direction toggle, and the player keyboard
shortcuts ⌘F / ⌘L / ⌘⇧E.

**Steps**

1. **Columns menu** — switch to List view (⌘2). Open the "Columns" menu
   in the browser toolbar.
   - **Expected:** Menu items for Rating, Date Modified, Title,
     Description, Reel, Scene, Shot, Take, Angle, Camera. Rating is
     checked by default.
2. **Toggle three columns on** — turn on Rating, Title, and Reel.
   - **Expected:** Three new columns appear after Size. Rating shows
     5-dot stars per row; Title pulls from the clip_metadata you set
     in Scenario 19. Empty values render as `—` in secondary colour.
   - **Note:** SwiftUI Table caps at 10 columns, so the optional
     column set is limited to the first 3 enabled (priority =
     `ListColumn.allCases` order). Enabling more displays only the
     first 3; toggle off one to surface another.
3. **Cross-launch persistence** — quit, relaunch. Columns selection
   survives.
4. **Sort direction toggle** — open Sort menu. Click "Ascending" /
   "Descending" entries at the bottom; also click an already-selected
   sort key to flip direction.
   - **Expected:** The toolbar Sort label shows the up/down arrow
     reflecting current direction; the table reorders accordingly.
     Direction persists across relaunch.
5. **⌘L loop mode** — in the player (List view, click a video; or
   Detail view), press ⌘L (or click the repeat button in the
   transport bar).
   - **Expected:** The repeat icon turns orange (filled) when on;
     when the clip reaches its end (or hits the out marker if I/O
     is set), the player seeks back to the in marker (or 0) and
     resumes playing. Pressing ⌘L again turns loop off.
6. **⌘F fullscreen** — press ⌘F.
   - **Expected:** Window enters macOS fullscreen mode. ⌘F or Esc
     exits.
7. **⌘⇧E export current frame** — play to an interesting frame,
   pause, press ⌘⇧E.
   - **Expected:** Save panel appears with default filename
     `<clipname>_t<seconds>.png`. After save, Finder opens with the
     PNG selected. Frame is the exact pause-time frame (verified by
     opening in Preview).

**Pass criteria**
- Columns add value (no crashes, values populate correctly).
- Sort direction works in both menu entries and the "click-again"
  flip on the selected key.
- Loop, fullscreen, export-frame shortcuts behave as documented.

---

## Scenario 21 — In-app Help: Keyboard Shortcuts cheat sheet + User Manual / Install entries

Covers the Shortcuts source-of-truth + the in-app cheat-sheet sheet +
SHORTCUTS.md generator + Help menu entries.

**Steps**

1. **Help menu items** — open the macOS Help menu in PurpleReel.
   - **Expected:** Items: Keyboard Shortcuts… (⌘?), PurpleReel User
     Manual, Install & Setup, SHORTCUTS.md (Reference File), Visit
     Kyno parity roadmap. macOS's default search field still appears
     above this list.
2. **Cheat sheet via menu** — click Keyboard Shortcuts… (or press
   ⌘?).
   - **Expected:** A 620×540 sheet opens with grouped sections
     (Browser / Player / Logging & Metadata / Convert / View /
     Window). Each row shows the combo in a monospace pill and the
     action text. The header shows the app version; the footer shows
     "N of M shortcuts" and a Close button (or ⎋).
3. **Search** — type "loop" into the search field.
   - **Expected:** Only the ⌘L row remains. The "N of M" counter
     updates. Clearing the field via the ✕ button restores all
     groups.
4. **SHORTCUTS.md** — click "SHORTCUTS.md (Reference File)".
   - **Expected:** The default Markdown viewer opens the file. The
     file lists the same shortcuts as the cheat sheet, grouped
     identically.
5. **User Manual** — click "PurpleReel User Manual".
   - **Expected:** USER_MANUAL.md opens. (Stub today — fuller content
     is on the documentation backlog.)
6. **Install & Setup** — click "Install & Setup".
   - **Expected:** Polite "INSTALL.md not found" alert with an
     explanation, until the doc lands. No crash.
7. **Source-of-truth round-trip** — open
   `Sources/PurpleReel/Help/Shortcuts.swift`, add a fake entry, run
   `swift Scripts/generate-shortcuts-md.swift`.
   - **Expected:** Generator reports "Wrote SHORTCUTS.md (N
     shortcuts)" with the count incremented; the new combo appears
     in `SHORTCUTS.md`. Build the app and confirm the cheat sheet
     shows it too. Remove the test entry and regenerate to clean up.

**Pass criteria**
- Cheat sheet renders, search works, ⌘? opens it.
- Help menu opens external markdown for files that exist; alerts
  cleanly for files that don't.
- `build-app.sh` runs the generator (look for "Regenerating
  SHORTCUTS.md…" in build output).
- Adding an entry to `Shortcuts.swift` propagates to both the
  in-app sheet and `SHORTCUTS.md`.

---

## Scenario 22 — Advanced Filter dropdown

Covers the multi-criteria Filter menu, the active-filter pills bar,
and the per-criterion match semantics (rating / tag / codec /
resolution / framerate / size / duration).

**Setup**
- Workspace contains a mix of clips with different rating values,
  codecs (H.264 + ProRes if possible), resolutions (1080p + 4K if
  possible), and frame rates.
- At least one clip has a tag (set via the Metadata pane).

**Steps**

1. **Open Filter menu** — toolbar shows a "Filter" button between
   the type chips and the Columns menu. Click it.
   - **Expected:** A categorized menu opens: Rating (≥★ through
     ≥★★★★★), Codec (H264 / HEVC / PRORES / DNXHR / CINEFORM),
     Resolution (8K / 4K / 1440p / 1080p / 720p / 480p), Frame Rate
     (23.98 / 24 / 25 / 29.97 / 30 / 50 / 59.94 / 60 fps), Size,
     Duration, Has Tag (only shown if any tags exist).
2. **Pin Rating ≥ ★★★★** — count goes from "X of Y" to filtered N.
   - **Expected:** Active-filter pills row appears under the toolbar
     in a soft-orange background. One pill says "Rating ≥ 4★" with
     an × button. Filter-menu icon turns orange + shows "(1)".
3. **Add Codec: PRORES** — second pill appears.
   - **Expected:** Only ProRes clips with ≥4★ rating remain. Pill
     count "(2)".
4. **Remove the rating pill** — click the × on "Rating ≥ 4★".
   - **Expected:** Only the codec pill remains; the rating
     restriction is lifted (all ProRes clips show again regardless
     of stars).
5. **Resolution preset** — add Resolution → 4K UHD.
   - **Expected:** Only 4K-resolution ProRes clips remain. Match
     handles portrait clips by using `max(width, height)`.
6. **Frame rate preset** — add Frame Rate → 23.98 fps.
   - **Expected:** Match tolerates the 23.976/24.000 boundary
     (±0.05). 24.000-fps clips do *not* match.
7. **Has Tag** — add Has Tag → <your tag>.
   - **Expected:** Pill appears; only clips with that tag remain.
8. **"Clear All" button** — at the trailing edge of the pills bar.
   - **Expected:** All pills removed in one click; toolbar Filter
     icon goes back to gray; full unfiltered count restored.
9. **Persistence across launches** — pin two criteria, quit, relaunch.
   - **Expected:** The same pills are restored. (Backed by
     `UserDefaults("activeFilters")` as a `;`-joined token string.)
10. **Type chip + advanced filter combined** — click the Video chip,
    then add a Filter > Resolution > 1080p.
    - **Expected:** Both apply (AND-combined). Switching the type
      chip back to "All" leaves the advanced filter in place.
11. **Empty active set behaviour** — clear filters. The pills row
    should disappear (toolbar shrinks back to 2 rows).
12. **Many criteria** — add 6+ filters. Pills should scroll
    horizontally inside the bar without overflowing the window.

**Pass criteria**
- Filter menu opens, every category lists the right options.
- Each pill matches its semantics; AND composition is correct.
- × on a pill, "Clear All" button, and "Clear All Filters" inside
  the menu all behave consistently.
- Pills bar shows only when criteria are active.
- Active filters round-trip across launches.

---

## Scenario 23 — Player Up/Down marker nav + Shift+Arrow 5-sec jumps

Covers two related player polish items: arrow-shift coarse jumps and
Up/Down marker (or in/out) navigation. Both work from the player key
handler (when the player has focus) and from the Playback menu (so
they fire system-wide while the app is frontmost).

**Setup**
- A video clip at least 30 seconds long.
- The clip has 2-3 markers added (M key) at known timecodes plus an
  in/out range set with I/O.

**Steps**

1. **Shift+→ jumps forward 5 s** — start at 0:00. Press Shift+→.
   - **Expected:** Playhead advances by exactly 5 seconds. Timecode
     readout shows ~0:05. Repeating moves to 0:10, 0:15, …
2. **Shift+← jumps back 5 s** — press Shift+← from 0:15.
   - **Expected:** Playhead returns to 0:10. Stops at 0:00 if you
     keep pressing (no negative seek).
3. **↓ jumps to next marker** — from 0:00, with markers at e.g.
   0:03, 0:12, 0:25, press ↓.
   - **Expected:** Playhead snaps to 0:03 (first marker after 0:00).
     Next ↓ press → 0:12, then 0:25. Further ↓ presses no-op once
     no anchor is ahead of the playhead.
4. **↑ jumps to previous marker** — from 0:25, press ↑.
   - **Expected:** Playhead snaps to 0:12, then 0:03, then no-op
     (no anchor before the playhead).
5. **In / Out points count as anchors** — set I at 0:08, O at 0:18.
   From 0:00, press ↓ four times.
   - **Expected:** Sequence is 0:03 → 0:08 (in) → 0:12 → 0:18 (out).
     Markers + I/O combine sorted into a single anchor list.
6. **Epsilon — landing on an anchor doesn't immediately re-fire** —
   from 0:00, ↓ to 0:03. Press ↓ again.
   - **Expected:** Advances to 0:08, not stuck on 0:03 (epsilon ±0.05s).
7. **Menu-bar firing** — open Playback menu. Verify items: Jump Back
   5 Seconds (Shift+←), Jump Forward 5 Seconds (Shift+→), Previous
   Marker (↑), Next Marker (↓). Click each.
   - **Expected:** Same behaviour as the in-player keystrokes.
8. **No markers + no I/O** — clear all markers, clear I/O. Press ↑/↓.
   - **Expected:** No-ops cleanly (no crash, playhead stays put).
9. **Cheat sheet** — Help → Keyboard Shortcuts… (⌘?). Search
   "marker" and "5".
   - **Expected:** Shift+← / Shift+→ / ↑ / ↓ entries appear in the
     Player group with the correct action labels.
10. **SHORTCUTS.md** — `cat SHORTCUTS.md | grep -E "Shift\+|marker"`.
    - **Expected:** Four matching rows generated from
      `Shortcuts.swift`.

**Pass criteria**
- Both Shift+arrow and ↑/↓ behave as documented from keyboard and
  menu.
- Anchor list correctly unions markers + in + out.
- Epsilon prevents the "stuck on an anchor" bug.
- Cheat sheet + SHORTCUTS.md reflect the four new combos.

---

## Scenario 24 — Batch metadata edit sheet (⌘⇧M)

Covers the per-field opt-in batch editor that applies log fields,
rating, and additive tags across the multi-selection.

**Setup**
- Workspace contains at least 5 clips. Some have existing tags
  (e.g. "alpha") and some have ratings.

**Steps**

1. **Open via menu** — pick 3+ clips (Grid view, Cmd-click). Menu
   bar → **Metadata → Edit Multiple…** (⌘⇧M).
   - **Expected:** Sheet opens titled "Edit Metadata for N clips"
     matching the count.
2. **No selection** — clear selection, open the Metadata menu.
   - **Expected:** "Edit Multiple…" is disabled.
3. **Apply checkboxes gate writes** — open sheet with selection.
   - **Expected:** Every row (Rating / Add Tags / Title /
     Description / Reel / Scene / Shot / Take / Angle / Camera) is
     greyed out until its Apply checkbox is ticked. The Apply
     button at the bottom-right is disabled until at least one row
     is ticked.
4. **Set rating across selection** — tick Apply Rating, click 4
   stars. Click Apply.
   - **Expected:** Sheet shows "Applied to N clips." in green and
     auto-dismisses after ~0.8s. Click any of the previously
     selected clips and confirm in the Metadata pane the rating is
     now 4. Clips NOT in the selection are untouched.
5. **Add tags (additive)** — select clips, one of which already has
   tag "alpha". Open sheet, tick Add Tags, type "beta", Return,
   "gamma", Return. Apply.
   - **Expected:** All selected clips now carry "alpha" (where
     pre-existing), "beta", and "gamma". The pre-existing "alpha"
     was NOT cleared on the clip that had it. New tags appear in
     the Filter menu's Has Tag submenu and in `knownTagNames`.
6. **Set Scene + Camera, leave others unchecked** — open sheet,
   tick Apply Scene = "2A", Apply Camera = "RED V-Raptor". Apply.
   - **Expected:** Every selected clip gets Scene and Camera set.
     Description / Reel / Shot / Take / Angle remain whatever they
     were per-clip (verify by clicking individual clips).
7. **Clearing a field** — tick Apply Scene with the field empty.
   Apply.
   - **Expected:** Scene is cleared on every selected clip
     (sanitize() converts empty to nil). Other fields untouched.
8. **Cancel** — open sheet, type into fields, click Cancel.
   - **Expected:** No writes happen. Selection's metadata
     unchanged.
9. **Returned but unsubmitted tag draft** — in the tag field, type
   "delta" but click Apply without pressing Return.
   - **Expected:** `commitTagDraft()` runs before Apply, so "delta"
     IS added to the selection's tags.
10. **Single-clip mode** — select exactly one clip (no multi-select).
    Open ⌘⇧M.
    - **Expected:** Sheet works identically; header says "Edit
      Metadata for 1 clip"; Apply writes to that one clip.
11. **Cheat sheet** — Help → Keyboard Shortcuts… (⌘?), search "edit
    multiple".
    - **Expected:** Row appears: `⌘⇧M` → "Edit Multiple metadata
      across selection".
12. **FCPXML round-trip carries batched fields** — after step 6,
    Send selected → "Save .fcpxml Only". Check the file:
    `grep -A1 metadata ~/Downloads/PurpleReel/exports/PurpleReel_*.fcpxml`.
    - **Expected:** Each `<asset-clip>` for a batched clip carries
      `<md key="Scene" value="2A"/>` and `<md key="Camera"
      value="RED V-Raptor"/>` (and Title / Description etc. for
      any other batched fields).

**Pass criteria**
- Sheet's per-field opt-in checkbox gating is reliable: unticked
  fields never write.
- Tags are additive only — no destructive replacement.
- Apply auto-dismisses after the green confirmation.
- Multi-select drives the target set; single-select still works.
- FCPXML emission picks up the batched fields.

---

## Scenario 25 — Polish round: rotate / remove / collapsible sidebar / grid slider

Four small Kyno-parity items bundled. Each step exercises one
specific binding or affordance.

**Setup**
- A clip selected with at least two markers + one subclip.
- Workspace + Devices sections expanded by default.

**Steps**

1. **⌘R rotate clockwise** — press ⌘R in the player.
   - **Expected:** Preview rotates 90° clockwise. The underlying
     file is untouched (verify by reopening in QuickLook or by
     transcoding — output matches source orientation).
2. **⌘⌥R rotate counter-clockwise** — press ⌘⌥R.
   - **Expected:** Preview rotates back through 0°. Repeat presses
     wrap through 0/270/180/90 cleanly.
3. **Playback menu** — open menu bar → Playback. Verify items
   "Rotate Clockwise (⌘R)" and "Rotate Counter-clockwise (⌘⌥R)"
   are present.
4. **⌥M remove marker** — seek the playhead to within a frame of
   marker A. Press ⌥M.
   - **Expected:** Marker A is removed from both the Log tab and
     the Metadata pane. The other marker remains.
5. **⌥M with no nearby marker** — seek to a position well away
   from any marker. Press ⌥M.
   - **Expected:** Removes the marker nearest to the playhead (no
     no-op). Use only with playhead near the intended target.
6. **⌥S remove last subclip** — press ⌥S.
   - **Expected:** The most recently created subclip is removed.
     The earlier subclip(s) stay.
7. **Disabled when no clip selected** — clear selection. Open
   Playback menu.
   - **Expected:** Remove Marker at Playhead, Remove Last Subclip,
     and all transport items that need a clip are disabled.
8. **Sidebar disclosure — Workspace** — click the "Workspace"
   section header.
   - **Expected:** Chevron flips from ▼ to ▶; the workspace tree
     collapses. Click again to expand.
9. **Sidebar disclosure — Devices** — same on the "Devices"
   header.
   - **Expected:** Devices list collapses/expands independently.
10. **Sidebar disclosure — Stats** — same on the "Stats" header.
11. **Disclosure persistence** — collapse Workspace, quit
    PurpleReel, relaunch.
    - **Expected:** Workspace remains collapsed (driven by
      `@AppStorage("sidebar.workspace.expanded")`). Devices and
      Stats keep their states too.
12. **Grid tile-size slider — Grid mode only** — switch to Grid
    view (⌘1). Toolbar row 1 shows a small slider with a 3×2
    rectangle icon between Sort and the count.
    - **Expected:** Slider visible in Grid view; absent in List
      (⌘2) and Detail (⌘3).
13. **Slider effect** — drag the slider left/right.
    - **Expected:** Tiles re-flow continuously. At minimum (100)
      tiles are dense; at max (320) they're large. Persists across
      relaunches via @AppStorage("gridTileSize").
14. **Cheat sheet** — Help → Keyboard Shortcuts… (⌘?). Search
    "rotate" and "remove".
    - **Expected:** ⌘R / ⌘⌥R rows under View; ⌥M / ⌥S rows under
      Logging & Metadata. SHORTCUTS.md `grep -E "Rotate|Remove"`
      shows the same.

**Pass criteria**
- ⌘R / ⌘⌥R rotate the preview; underlying file is untouched.
- ⌥M removes the nearest marker; ⌥S removes the latest subclip.
- All three sidebar sections collapse independently and persist.
- Grid tile slider lives only in Grid view, persists, and re-flows
  cells continuously.
- Cheat sheet + SHORTCUTS.md reflect all four new combos.

---

## Regression triggers

After **any** change, re-run **at minimum**:

- Scenario 0 (clean launch)
- Scenario 1 (scan + thumbnails)
- Scenario 2 (player + LUT)
- Scenario 3 (logging round-trip across relaunches)
- `./run-tests.sh` (28 unit tests should all pass)

After any change to the **transcode / backup / SFTP / FCPXML /
AI** code paths, re-run the scenario(s) covering that area.

After any change to **window/sidebar layout**, re-run Scenario 15.

After any change to **multi-select / Convert submenu / Convert
dialog / per-asset progress overlays**, re-run Scenario 18.

After any change to the **clip_metadata schema / Metadata tab /
FCPXML metadata emission**, re-run Scenario 19.

After any change to **optional List columns / sort direction /
player keyboard shortcuts**, re-run Scenario 20.

After any change to **`Shortcuts.swift` / `ShortcutsCheatSheet.swift`
/ `Scripts/generate-shortcuts-md.swift` / Help menu**, re-run
Scenario 21.

After any change to **`FilterCriterion` / activeFilters /
tagIndex / Filter toolbar menu / active-filter pills bar**, re-run
Scenario 22.

After any change to **`PlayerController.jumpSeconds(_:)` /
`seekToAnchor(direction:markerTimes:)` / PlayerView key handler /
Playback menu / `onJumpMarker` plumbing**, re-run Scenario 23.

After any change to **`BatchMetadataChange` /
`AppState.applyBatchMetadata(_:)` / `BatchMetadataSheet`**,
re-run Scenario 24.

After any change to **`PlayerController.rotateBy(_:)` /
`AppState.removeMarkerNearestPlayhead(...)` /
`removeLastSubclipForSelection()` / sidebar `sectionHeader(...)` /
grid `gridTileSize` slider**, re-run Scenario 25.
