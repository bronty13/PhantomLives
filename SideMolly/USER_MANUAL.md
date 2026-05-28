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
  type: 🎬 Content, 🎁 Custom, or 📅 FanSite.
- **Ship it back** — compose a post-bundle ZIP that records what you
  posted; Molly ingests it to close the loop. The ZIP lands in
  `~/Downloads/Molly post-bundles/<uid>-post.zip`, and a plain
  `<uid>-post/` folder is written next to it holding the same contents
  (report, notes, posting log, artifacts) — open that folder to browse
  the artifacts directly, without unzipping.

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
