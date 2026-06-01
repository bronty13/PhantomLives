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
- **Import a text file** with the **Import…** button in the editor toolbar — pick
  a Markdown, plain-text, or RTF file and its contents drop into the body. (RTF
  comes in as plain text.) If the entry is empty the file becomes the body; if
  you've already written something, the file is added below it after a `---`
  divider, so nothing you typed is lost. This brings the text *into the entry*;
  to attach a file as media instead, use **Add from Files…** in the Media row.
- Set your **mood** with the 0–5 stars. Tap a star to set it; tap the same star
  again to clear it.
- Add **tags** by clicking the chips under the title. Manage the tag list (and
  colors) in the **Tags** section.

Edits save automatically a beat after you stop typing, and again when you switch
entries.

### Templates

If you write the same kind of entry often (a daily check-in, a gratitude list),
save it as a **template**. Click the little arrow on the **New Entry** toolbar
button to start an entry **From template**, write a **Blank Entry**, or open
**Manage Templates…**. A template's body can include tokens that fill in
automatically when you use it: `{{date}}`, `{{date_long}}`, `{{time}}`,
`{{weekday}}`, and `{{year}}`. PurpleDiary starts you off with two (Daily
check-in, Gratitude) — edit or delete them freely.

## Journals

Keep separate notebooks — Personal, Work, Travel, a dream journal — each with its
own entries.

- The **JOURNALS** list lives at the bottom of the sidebar. **All Journals** shows
  everything; click a single journal to focus just its entries (Timeline,
  Calendar, Search, and Insights all narrow to it).
- Click the **＋** to create one. Right-click a journal to **rename**, **recolor**,
  **hide**, or **delete** it. When you delete a journal that has entries, you
  choose whether to **move them to "Journal"** (nothing lost) or **delete them
  along with the journal**.
- New entries go into whichever journal you're currently viewing (or the default
  if you're on All Journals). Move an entry between journals with the **journal
  menu** in the editor header (next to the date).

### Hidden journals

Mark a journal **Hidden** (right-click → *Hide*) to keep it private: its entries
disappear from the Timeline, Calendar, Search, and Insights, and it shows a 🔒 in
the sidebar. Click the locked journal and authenticate (Touch ID, your device
password, or your passphrase) to reveal it **for this session** — it locks itself
again when you relaunch PurpleDiary.

> Note: "hidden" means *hidden from view*. The entries are still stored with the
> same strong encryption as the rest of your journal — they're just kept out of
> sight behind your unlock. For a stronger guarantee, turn the journal into a
> **Vault** (below).

### Vault journals (sealed under their own passphrase)

A **Vault** is the strongest privacy option. The titles and text of every entry
in a vault journal are sealed under a passphrase that's *yours alone* — they stay
encrypted **even while PurpleDiary is open**, until you type that passphrase for
the session. (A hidden journal is only filtered from view; a vault's entries are
genuine ciphertext on disk.)

**Make a journal a vault:** right-click it → **Make Vault…**. You'll set a
passphrase and paste your 24-word recovery key. PurpleDiary then seals every
existing entry in that journal. The recovery key matters: if you ever forget the
passphrase, it's the only other way in — so a forgotten passphrase is never a
permanent lockout. (For the same reason, **anyone with your recovery key can open
your vaults** — guard it like a seed phrase.)

**Day to day:** a locked vault shows a 🛡️ lock in the sidebar. Click it and enter
the passphrase to unlock it **for this session** — it re-seals automatically when
you relaunch PurpleDiary or lock the app (⌘L). While locked, a vault's entries are
left out of the Timeline, Calendar, Search, Insights — **and out of exports**, so
a sealed journal never leaks into a backup file you share.

From a vault's right-click menu you can also **Lock Vault Now**, **Change Vault
Passphrase…**, or **Remove Vault…** (which decrypts its entries back to normal
storage — still encrypted at rest like everything else, just no longer behind the
separate passphrase). Forgot the passphrase? Click the vault and choose **Forgot
passphrase?** to unlock with your 24-word recovery key instead.

> Everything here is offline. There is no cloud, no server, and no way to reset a
> vault passphrase from outside — the passphrase and recovery key never leave your
> Mac, and PurpleDiary stores neither in readable form.

## Reflecting

- **On This Day** — a sidebar section that gathers entries you wrote on today's
  date in earlier years, grouped by "1 year ago," "2 years ago," and so on. It's
  just a look-back over your own journal — nothing leaves your Mac. Click an
  entry to open it. (It follows your journal selection, and hidden journals stay
  hidden here too.)
- **Writing prompts** — start a new entry and, while it's blank, a little ✨
  prompt appears below your photos (e.g. *"What surprised you today?"*). Tap
  **Use** to drop it into the entry as a quote you can write under, or the
  shuffle button to see another. The prompt is the same all day, and the whole
  prompt library ships inside the app — nothing is fetched or generated online.

## Browsing

- **Timeline** — all entries, newest first, grouped by month. Click one to open
  it; right-click to delete.
- **Calendar** — a month grid shaded as a **heatmap**: the more you wrote on a
  day, the deeper its color (a Less→More key sits under the grid). Days with more
  than one entry show the count, and today has a ring. Click a day to jump to its
  entry (or start a new one there); hover for the day's entry and word counts.
  Use the arrows to change month.
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

**From Files** — click **Add from Files…** to choose **photos, videos, audio,
PDFs, or any other file** from anywhere on your Mac. Videos, audio, PDFs, and
other files are kept exactly as-is; photos are scaled down to a sensible size.
(Apple Photos only holds photos, so audio, PDFs, and documents come in through
Files.)

**Viewing & playback** — attached media shows up as thumbnails on the entry
(audio shows a music note, PDFs a first-page preview, other files a doc icon).
**Click a thumbnail** to open it: photos display fit-to-window, videos play in a
built-in player, audio opens a compact player (play/pause or Space, scrubber,
running time), PDFs open in a scroll/zoom reader, and any other file shows its
name and size. Playable items carry a ▶ badge. The viewer has a **Save a Copy…**
button to write the original back out to disk. Hover a thumbnail and click the ✕
to remove it from the entry.

**Putting media inside your writing** — you can place any attachment *within*
the entry text, with a caption and words before and after it. Right-click an item
in the strip and choose **Insert into entry text**; a little reference like
`![caption](pd-attachment://…)` drops into the body. Type a caption between the
`[ ]`, and move the line wherever you want it in **Write** mode — then switch to
**Preview** and the photo (or video/audio/PDF) shows right there in the story,
tappable to open full size. The item still lives in the strip too, for managing.

Everything is copied **into your encrypted journal** (stored right inside the
database, so it's protected by the same encryption and included in backups) —
nothing is ever uploaded. One thing to know: because videos, audio, PDFs, and
files are stored uncompressed inside the database, a large one makes both your
database and each launch backup bigger. Keep big attachments occasional.

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

> **Vaults and exports:** a locked vault journal is skipped entirely — its sealed
> entries never appear in an export. Unlock a vault first if you want its entries
> included (they'll be written as normal readable text in the file, so only export
> a vault to somewhere you trust).

## Importing from another app

Switching from another journal app — or moving entries between Macs? Choose
**File → Import Journal…** (⇧⌘I), pick a `.json` file, and PurpleDiary adds its
entries to your journal (it never overwrites what's already there).

- **PurpleDiary** — re-import one of your own JSON exports. Your entries come
  back into their original journals, with mood and tags. (Photos/videos,
  trackers, and people links aren't stored in the JSON export, so those don't
  come back through import — keep the encrypted backups for a full restore.)
- **Day One / Journey / Diarium** — export from that app, **unzip** it, and pick
  the `.json` inside. Entries land in a new journal named for the source. For
  **Day One**, leave the photos/videos folders next to `Journal.json` when you
  pick it — their media is brought in and, where Day One had a photo *inline* in
  the text, it's placed back **inline at that spot** (with its caption) so the
  story reads the way you wrote it. These
  importers are built to each app's documented format; give the result a quick
  look and let me know if anything's off.

To remove an import you were just trying out, right-click its journal →
**Delete Journal…** and choose **Delete journal and its entries** (the other
option just moves them into your default journal).

The sheet auto-detects the format (or you can choose it) and tells you how many
entries it added.

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

## Daily reminder

Want a nudge to write? In **Settings → Reminders**, turn on **Remind me to
journal each day** and pick a time. PurpleDiary will pop a gentle notification
then. It's an ordinary local reminder — nothing is sent anywhere — and the first
time you enable it, macOS may ask you to allow notifications for PurpleDiary. You
can change the time, turn it off, or silence it from System Settings →
Notifications whenever you like.

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
