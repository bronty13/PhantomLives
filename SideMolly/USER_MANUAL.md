# SideMolly — User Manual

> **Phase 0 placeholder.** Content lands as features ship.

SideMolly is a workbench for Molly bundles. When Molly publishes a bundle
(content, custom, or fan-site), drop the resulting ZIP into SideMolly and
work through three stages — **edit**, **process**, **post** — then send a
post-bundle back to Molly to record what actually happened.

## What works in Phase 0

- The app installs and launches.
- Sidebar shows three tabs: **Inbox** (placeholder), **Settings**, and
  **Manual** (this file).
- **Settings → Backup** is fully wired:
  - Toggle auto-backup-on-launch (default **on**, 5-minute debounce)
  - Set a custom backup folder (or fall back to `~/Downloads/SideMolly backup/`)
  - Set retention days (0 = keep forever, default 14)
  - **Run Backup Now**
  - **Recent backups** list with per-row Test / Restore / Reveal actions
  - Last-backup timestamp + status line

## FanSite posting (📅 Bundle → Post)

FanSite bundles are posted before the start of each month, on a
calendar cadence, to a **fixed roster of sites per persona**:

| Persona | Sites |
|---|---|
| **CoC** | OnlyFans · ManyVids · Niteflirt |
| **PoA** | OnlyFans · Niteflirt · LoyalFans |
| **Sheer (Sa)** | *(none — Sheer has no fan-sites)* |

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
     own) into a dedicated folder. Use **📋 Copy folder path** or
     **👁 Reveal folder**, then point the site's upload dialog there.
     Because the folder holds only that day's media, you can't grab
     the wrong files.
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
action with a timestamp, site, day, and URL. It's also written into
the post-bundle ZIP (`posting-log.json`) so Molly can reconcile what
went live when you ship the bundle back.

## What's coming

See [PLAN.md](PLAN.md) §11 for the 13-phase plan.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘+S / Ctrl+S | Toggle the sidebar |
