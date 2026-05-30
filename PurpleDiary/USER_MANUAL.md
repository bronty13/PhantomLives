# PurpleDiary — User Manual

PurpleDiary is your private journal. Everything stays on your Mac — there's no
account and nothing leaves your computer unless you choose to export or sync it.

## Writing an entry

- Press **⌘N** (or the pencil in the toolbar) to start a new entry. It opens in
  the **Timeline** with the editor focused.
- Set the **date and time** the entry is about with the date field at the top —
  you can backdate freely, and you can have as many entries per day as you like.
- Give it a **title** if you want (optional — the timeline falls back to a body
  snippet).
- Write the body in **Markdown**. Use the **Write / Preview** toggle to see it
  rendered. The live word count is in the editor's top-right and in the sidebar
  footer.
- Set your **mood** with the 0–5 stars. Tap a star to set it; tap the same star
  again to clear it.
- Add **tags** by clicking the chips under the title. Manage the tag list (and
  colors) in the **Tags** section.

Edits save automatically a beat after you stop typing, and again when you switch
entries.

## Browsing

- **Timeline** — all entries, newest first, grouped by month. Click one to open
  it; right-click to delete.
- **Calendar** — a month grid. Days with entries get a dot. Click a day to jump
  to its entry (or start a new one on that day). Use the arrows to change month.
- **Search** — type to find entries by title, body, tag, or person. Results are
  ranked: a title match beats a body match. Click a result to open it.

## People & tags

- **People** — keep a list of the recurring people in your life; link them to
  entries (linking UI expands in a later release).
- **Tags** — add a tag with a name and color, recolor existing ones, or delete.
  PurpleDiary seeds a starter set (personal, work, travel, health, ideas,
  gratitude) on first launch.

## Backups

PurpleDiary backs up your whole journal automatically **every time you open the
app** (skipping the run if one happened in the last five minutes). Backups are
zip files in `~/Downloads/PurpleDiary backup/`.

In **Settings → Backup** you can:

- Turn auto-backup on/off, change the folder, and set how many days to keep
  (0 = keep forever).
- **Run Backup Now** on demand.
- **Test** a backup (checks it's a valid journal without touching your live
  data) and **Restore** from one (a safety backup of your current journal is
  written first).
- **Reveal in Finder**.

## Settings

- **General** — daily word goal, week-start day, restore sample entries, and the
  app version + database location.
- **Appearance** — light/dark/system and the accent color.
- **Lock** — toggles for requiring a passcode and Touch ID. *(This phase the
  toggles persist but the lock screen itself is still being built.)*
- **Backup** — described above.

## What's coming

The "auto-assembled day" features that define Diarium — pulling in your photos,
calendar, location, and weather — plus mood/tracker graphs, a map of your
entries, encryption-at-rest, and bring-your-own-cloud sync are planned for the
next phases. See `SCOPING.md` in the project for the full roadmap.
