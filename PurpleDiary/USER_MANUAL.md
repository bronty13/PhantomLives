# PurpleDiary — User Manual

PurpleDiary is your private journal. Everything stays on your Mac — there's no
account and nothing leaves your computer unless you choose to export or sync it.
Your journal is **encrypted at rest**: the database on disk is unreadable
without the key, which lives in your Mac's Keychain.

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
- **Insights** — a dashboard of your journaling: total entries and words, days
  journaled, average mood, your current and longest writing streaks, a
  mood-over-time line, entries and words per month, which tags you use most, and
  a line chart for each tracker you keep (see below). It's all computed from your
  entries on your Mac — nothing is sent anywhere.

## Photos, Video & Audio

PurpleDiary can pull in the photos you took on an entry's date so your day
arrives pre-assembled — and you can add photos, videos, or audio from anywhere
on your Mac too.

**From Apple Photos** — in the editor, find the **Media** row and click **Add
from Photos**.

- The first time, macOS asks for permission to your photo library — choose
  **Allow Access to All Photos** (or **Select Photos…** to share only some).
  You can change this later in System Settings → Privacy & Security → Photos.
- A grid of the photos from the entry's date appears. To look elsewhere, use the
  **date picker** at the top to jump to any other day, or tick **Show all
  recent** to browse your most recent photos regardless of date.
- Click to select the ones you want, then **Add**.

**From Files** — click **Add from Files…** to choose **photos, videos, or audio**
(mp3, m4a, wav, …) from anywhere on your Mac. Videos and audio are kept exactly
as-is (not re-compressed); photos are scaled down to a sensible size. (Apple
Photos only holds photos, so audio comes in through Files.)

**Viewing & playback** — attached media shows up as thumbnails on the entry
(audio shows a music-note glyph). **Click a thumbnail** to open it: photos
display fit-to-window, videos play in a built-in player, and audio opens a
compact player with play/pause (or the Space bar), a scrubber, and the running
time. Playable items carry a ▶ badge. The viewer has a **Save a Copy…** button
to write the original back out to disk. Hover a thumbnail and click the ✕ to
remove it from the entry.

Everything is copied **into your encrypted journal** (stored right inside the
database, so it's protected by the same encryption and included in backups) —
nothing is ever uploaded. One thing to know: because videos and audio are stored
uncompressed inside the database, a large file makes both your database and each
launch backup bigger. Short clips are best.

## Trackers

Trackers let you log a number on each entry and watch it trend over time —
cups of water, hours of sleep, pages read, whether you exercised.

- Open the **Trackers** section to create one. Give it a name, pick a **kind**,
  choose a color, and (for numbers) an optional **unit**:
  - **Number** — any quantity, with your unit (e.g. `6 cups`, `3 km`).
  - **Duration** — minutes, shown back as `1h 30m`.
  - **Yes / No** — a simple did-I-or-didn't-I.
- When you write or edit an entry, a **Trackers** row appears below the tags.
  Type a value (or pick — / No / Yes) to log it for that day. Clearing the field
  un-logs it — an empty tracker is never recorded as a zero.
- In **Insights**, each tracker with data gets its own line chart in its color,
  showing the daily average over time. (Days with more than one entry are
  averaged into a single point.)
- Deleting a tracker removes its logged values everywhere but leaves your
  entries untouched.

## Exporting your journal

Want a copy of your journal outside the app? Choose **File → Export Journal…**
(⇧⌘E), or open **Settings → General → Export**, and pick a format:

- **Markdown** — one plain-text document, entries grouped by month, with a
  little metadata line (date, mood, tags, people) above each entry's text.
  Opens in any editor or a note vault like Obsidian or Bear.
- **HTML** — a single self-contained web page (nicely styled, no extra files)
  you can open in any browser.
- **PDF** — the same layout as the HTML, paginated — handy for printing or
  keeping a fixed archive.
- **JSON** — a complete, structured copy of every entry, tag, person, and
  tracker (with the values you logged), plus an attachment count per entry. This
  is the one to keep if you ever want to re-import your journal later. (Markdown
  and HTML exports show each entry's logged tracker values on a 📊 line and a 🖼️
  attachment count too.) Exports note how many attachments (photos, videos, and
  audio) an entry has, but the media files themselves stay safely inside your
  encrypted journal and its backups.

Files are saved to **`~/Downloads/PurpleDiary/`** by default (you can change the
folder in Settings → General → Export), named
`PurpleDiary-Journal-<date-time>.<format>`. After an export, tap **Reveal in
Finder** to jump straight to the file. Everything stays on your Mac — exporting
just writes a file; nothing is uploaded anywhere.

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

## Locking & encryption

Your journal database is **encrypted on disk** (SQLCipher / AES-256). The key
is generated on first launch and stored in your Mac's login Keychain, so the app
opens silently for you but the file is useless to anyone who copies it off your
Mac.

**Recovery key.** On first launch PurpleDiary shows you a **24-word recovery
key** and asks you to save it (write it down, print it, or store it in a password
manager). It can unlock your journal if your Mac's Keychain entry is ever lost
(e.g. after an OS reinstall). Treat it like a seed phrase — anyone with it can
read your journal. You can regenerate it anytime in **Settings → Security**.

**App-lock.** Turn on **Settings → Security → Require unlock** to put a lock
screen in front of the app:

- **Lock on launch** shows the lock screen each time you open PurpleDiary.
- The app also locks when it loses focus.
- Unlock with **Touch ID** / your Mac password — or, if you set a passphrase,
  by typing it.
- **Touch ID only** disables the password fallback (recover by quitting and
  turning it back off if your sensor stops working).
- **Lock Now** (⌘L, or the menu) locks immediately.

**Passphrase (optional).** Add a passphrase for a second layer beyond the
Keychain — then even someone who can unlock your Mac's Keychain can't open the
journal without it. Change or remove it anytime in Settings → Security.

If the Keychain key is ever lost, PurpleDiary shows a recovery screen where you
enter your 24-word recovery key — or reset and start fresh (your old, unreadable
data is quarantined on disk rather than deleted, just in case).

**Want the full story?** Open **Help → Security & Privacy whitepaper…** to read
the complete write-up of how your journal is protected — what's encrypted, what
isn't, how the recovery key works, and how to verify the claims yourself. It's
the same document as `Docs/SECURITY.md` in the project, rendered right inside the
app.

## Settings

- **General** — daily word goal, week-start day; restore the original sample
  entries, **add 100 sample entries** to try things at scale, or **remove all
  sample entries** the app generated; the **Export** controls (format + folder,
  described above); app version + database location.
- **Appearance** — light/dark/system and the accent color.
- **Security** — encryption status, app-lock toggles, Touch ID options,
  passphrase, and recovery-key management (above).
- **Backup** — described above. Backups capture the encrypted database plus the
  key envelopes, so a restore on another Mac can be unlocked with your passphrase
  or recovery key.

## What's coming

More of the "auto-assembled day" features that define Diarium — pulling in your
calendar, location, and weather (photos already work, above) — plus a map of your
entries and bring-your-own-cloud sync are planned for the next phases. See
`SCOPING.md` in the project for the full roadmap.
