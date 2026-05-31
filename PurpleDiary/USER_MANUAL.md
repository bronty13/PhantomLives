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

## Settings

- **General** — daily word goal, week-start day; restore the original sample
  entries, **add 100 sample entries** to try things at scale, or **remove all
  sample entries** the app generated; app version + database location.
- **Appearance** — light/dark/system and the accent color.
- **Security** — encryption status, app-lock toggles, Touch ID options,
  passphrase, and recovery-key management (above).
- **Backup** — described above. Backups capture the encrypted database plus the
  key envelopes, so a restore on another Mac can be unlocked with your passphrase
  or recovery key.

## What's coming

The "auto-assembled day" features that define Diarium — pulling in your photos,
calendar, location, and weather — plus mood/tracker graphs, a map of your
entries, and bring-your-own-cloud sync are planned for the next phases. See
`SCOPING.md` in the project for the full roadmap.
