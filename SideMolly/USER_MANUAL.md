# SideMolly — User Manual

SideMolly is a workbench for Molly bundles. When Molly publishes a bundle
(content, custom, or fan-site), drop the resulting ZIP into SideMolly and
work through three stages — **edit**, **process**, **post** — then send a
post-bundle back to Molly to record what actually happened.

## Getting started

- **Ingest a bundle** — drag a Molly bundle `.zip` onto the window, or
  drop it in the watched folder (Settings → Watched folder) and it's
  picked up automatically. SideMolly verifies it against `hashes.json`
  and extracts it into a per-bundle workspace.
- **Work a bundle** — open it from the **Inbox** and move through the
  **Edit → Process → Post** tabs. The Post tab adapts to the bundle
  type: 🎬 Content, 🎁 Custom, or 📅 FanSite. ▶️ YouTube (and any other
  type Molly adds later) gets a generic per-platform posting checklist.
- **Rotate clips** — in Edit → Step 1, click a tile to cycle its rotation,
  or tick several clips and use **Rotate selected** / **Rotate all** to turn
  them 90° clockwise at a time. Rotation is applied when you process/assemble.
- **Working title** — the Edit tab has a ✏️ **Working title** field. Edit it
  to change the title used for the master-cut filename, title card, Dropbox
  folder, and posting. Molly's original is preserved (shown as an "edited
  from…" hint), the change is logged in the post-bundle, and **Reset to
  original** reverts it.
- **Ship it back** — compose a post-bundle ZIP that records what you
  posted; Molly ingests it to close the loop. The ZIP lands in
  `~/Downloads/Molly post-bundles/<uid>-post.zip`, and a plain
  `<uid>-post/` folder is written next to it holding the same contents
  (report, notes, posting log, artifacts) — open that folder to browse
  the artifacts directly, without unzipping.
- **Mark it complete** — once you're done with a bundle, click **✓ Complete**
  on its Inbox row to tuck it out of the default view. After **Send to Molly**
  succeeds, SideMolly also offers to complete the bundle in one click.
- **SideMolly Summary** — generate a one-page PDF that captures the whole
  bundle (metadata, sampled frames, transcripts, processing log). It rides along
  to Dropbox with the assembled master cut. See below.

## SideMolly Summary (Distribute → Generate summary PDF)

The **SideMolly Summary** is a single PDF that captures everything about a
bundle in one place, in this order:

1. **Metadata** — Title, Working title (only if you changed it), Description
   (the typed text, or — for an audio description — the transcribed audio),
   Categories, Go-Live Date, and Date Processed (when the master cut was
   assembled). Right after Date Processed, the **assembled file** details:
   filename, file size (MB), length (MM:SS), and the SHA-256 hash so anyone
   can verify the `.mp4` they received. **Custom** bundles also show the
   Site/URL, who it's delivered to, and the Price (or "Handled in platform").
   The fields shown adapt to the bundle type.
2. **Frames** — a grid of frames sampled from the bundle's videos. The total
   number of frames is the count you set in Settings (default 30), spread
   evenly across the videos — three videos at 30 frames means ten from each,
   evenly spaced along each clip. Frames are taken **after** any rotation you
   set on the Edit tab, so they're always the right way up. (A bundle with no
   video falls back to a grid of its image thumbnails, also righted.)
3. **Transcript** — every video's transcript, concatenated and tidied up
   (blank lines removed, sentences capitalized and ended with a period). If a
   bundle hasn't been transcribed yet, run **Transcribe** on the Edit tab
   first.
4. **Processing log** — the full, time-ordered log of everything SideMolly did
   to the bundle.

Open a bundle, go to the **Distribute** tab, and click
**📄 Generate summary PDF** — it writes the PDF into the bundle's workspace
(`auto/<Title> — Summary.pdf`) and opens it for you. You don't have to do this
by hand for delivery, though: every time you **Copy to Dropbox**, SideMolly
regenerates the summary fresh and copies it next to the assembled master cut.

**Frame count** lives in **Settings → 📄 Summary** (default **30**). It sets how
many frames the summary samples, and also how many thumbnails go in the
post-bundle sent back to Molly.

## Edit defaults (Settings → ✏️ Edit defaults)

The **Edit** tab's image and video op toggles (Watermark, Strip EXIF /
metadata, Rename) start from these global defaults whenever you open a bundle.
They apply to every persona — there's no per-persona variation. **Rename** is
on by default. You can still flip any toggle per-bundle before you process;
this pane just sets the starting point.

## Organizing the Inbox

The Inbox opens on **Active** bundles — everything you haven't finished yet.
The toolbar at the top keeps it manageable:

- **Active | Completed | All** — the segmented toggle switches which bundles
  you see. *Active* hides anything you've marked complete; *Completed* shows
  only those; *All* shows everything.
- **Type / Persona chips** — narrow to one bundle type (🎬 content, 🎁 custom,
  📅 fansite, ▶️ youtube) or one persona (CoC, PoA, Sa). Click **All** (or the
  active chip again) to clear it.
- **Sort** — newest or oldest first by ingested date.
- **Date** — restrict to bundles ingested within a from/to window.
- **Search** — free-text match on title or UID.
- The `n of N` readout shows how many bundles match versus the total.

Each row has actions on the right:

- **✓ Complete** — mark an active bundle done; it leaves the Active view and
  picks up a green *Completed &lt;date&gt;* stamp.
- **↩ Reactivate** — bring a completed bundle back to Active.
- **🗑 Delete** — remove a bundle for good. You'll get a *Delete? Yes / Cancel*
  confirm first. Deleting removes SideMolly's record and its working folder
  (`~/Downloads/SideMolly/work/<uid>/`) but **leaves** any post-bundle you
  already sent (`~/Downloads/Molly post-bundles/<uid>-post.zip`) and the
  original incoming ZIP untouched.

Completing is reversible and only affects what shows in the Inbox — it doesn't
touch files, postings, or the post-bundle. Deleting is permanent.

## YouTube intro / outro clips (Settings → Intro / Outro)

For ▶️ **YouTube** bundles, the assembled master can be bookended with a
persona-specific **intro** and **outro** clip:

```
intro → clip1 ⤫ clip2 ⤫ … ⤫ clip[n] → outro     (⤫ = cross-dissolve)
```

The intro **replaces** the generated title card for YouTube bundles. Both are
**off by default** — nothing changes until you upload a clip and turn it on.

- Open **Settings → Intro / Outro**. There's a card per persona, each with an
  **Intro** and an **Outro** row.
- Click **Upload…**, pick a video (`.mp4`/`.mov`/`.m4v`/`.webm`), then tick
  **Enabled**. The same clip is reused for every YouTube bundle of that persona
  until you **Replace…** or **Remove** it.
- Intro/outro are resized to the bundle's format (16:9 or 9:16) and get the
  persona watermark + audio polish, just like the content clips, so the
  cross-dissolves join cleanly.

Leave either off and the master simply skips it (intro off → straight into the
clips; both off → just the clips). This only affects YouTube bundles — Content,
Custom, and FanSite masters are unchanged (title card + clips).

## FanSite posting (📅 Bundle → Post)

FanSite bundles are posted before the start of each month, on a
calendar cadence, to a **fixed roster of sites per persona**:

- **CoC** → OnlyFans · ManyVids · Niteflirt
- **PoA** → OnlyFans · Niteflirt · LoyalFans
- **Sheer (Sa)** → none — Sheer has no fan-sites

### First-time setup

Open a FanSite bundle → **Post** tab. If no sites are configured yet,
click **🚀 Set up fan-sites for {persona}** (or **📅 Seed fan-sites**
in Settings → Platforms). This creates the canonical roster with the
persona's color. It's idempotent and never overwrites edits you've
made — run it whenever a roster looks incomplete.

### Posting a month

1. The banner shows the **persona color**, **month**, and **title**,
   each with a **📋 copy** chip.
2. Pick a **site tab** at the top. Each tab shows progress
   (`✓ posted / total`). Do one site fully, then move to the next.
3. Click a day in the calendar. The day card opens with:
   - **Copy chips** for Persona · Date · Title · Message.
   - **📁 Day media** — SideMolly stages exactly that day's files
     (rotated, EXIF stripped, **no watermark** — the sites add their
     own) into a dedicated folder under
     `~/Downloads/SideMolly/FanSite/<persona> <month> <title>/Day NN/`.
     That location is browsable: in the site's upload dialog pick
     **Downloads → SideMolly → FanSite**, or press **⌘⇧G** and paste
     the path from **📋 Copy folder path**. **👁 Reveal folder** opens
     it in Finder. Because the folder holds only that day's media, you
     can't grab the wrong files.
   - **🚀 Open {site}** (if a URL is set), **📋 Copy message**.
4. After uploading, tick the **posted** checkbox (untick to undo a
   mistaken check), or click **✓ Mark posted & advance** to record it
   and jump to the next pending day for that site. Fan-site posting is
   just posted-or-not — there's no status menu and no URL to record.

You can stop any time; your place is saved. Re-opening the bundle
auto-focuses the next pending day for the active site.

### Resetting

**↺ Reset {site}** clears one site's posting state; **↺ Reset all
sites** clears the whole bundle. Both are confirm-gated, and the
**posting log keeps the history** regardless.

### Posting log

The **📝 Posting log** panel records every posted / unposted / reset
action with a timestamp, site, and day. It's also written into the
post-bundle ZIP (`posting-log.json`) so Molly can reconcile what went
live when you ship the bundle back.

## Appearance (Settings → 🎨 Appearance)

Pick SideMolly's theme:

- **Dark** — the default.
- **Light**.
- **Auto** — follows your macOS Light/Dark setting and switches live
  when the system appearance changes.

The choice is remembered across launches and applies immediately
(no restart, no flash on startup).

## Where SideMolly keeps files

- **Bundle media you work with** lives under `~/Downloads/SideMolly/`:
  extracted and processed files at `~/Downloads/SideMolly/work/<uid>/`,
  and the FanSite per-day upload folders at
  `~/Downloads/SideMolly/FanSite/`. Keeping them here means they're
  reachable from a site's browser upload dialog.
- **The database and settings** live in
  `~/Library/Application Support/com.phantomlives.sidemolly/` — that's
  what the launch backup archives (and why backups stay small: they
  don't carry the bundle media).

Upgrading from an older version moves your existing workspace into
`~/Downloads/SideMolly/work/` automatically on first launch.

## Backup (Settings → 💾 Backup)

SideMolly auto-backs up its database on launch (default **on**, with a
5-minute debounce so quick relaunches don't pile up archives).

- Set a custom backup folder, or fall back to
  `~/Downloads/SideMolly backup/`.
- Set retention days (`0` = keep forever, default 14).
- **Run Backup Now** ignores the debounce.
- **Recent backups** lists archives with per-row **Test** / **Restore**
  / **Reveal** actions. Restore always writes a pre-restore safety
  backup first.

## Keyboard shortcuts

- **⌘S / Ctrl+S** — toggle the sidebar.
