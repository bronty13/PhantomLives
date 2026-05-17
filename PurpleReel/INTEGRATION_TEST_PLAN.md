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
