# Molly — User Manual

This guide is written for the creator using Molly day to day, not for developers. If you ever get stuck, send Robert a screenshot in Slack and he can usually figure it out.

> Phase 5 is live — and that's all five phases shipped. **Data export**, **Updates**, plus everything before them.

## Opening Molly

### macOS

Double-click **Molly** in your Applications folder, or hit ⌘+Space and type "Molly".

### Windows

Double-click the Molly icon on your Desktop or Start menu.

If Windows SmartScreen says "Windows protected your PC", click **More info** → **Run anyway** the first time (the installer is signed by Robert, but it's a new app so SmartScreen hasn't seen many users yet).

## The persona switcher

The pills at the top right are the personas:

- **CoC** — Curse Of Curves (baby pink)
- **PoA** — Princess of Addiction (red & black)
- **Sa**  — Sheer Attraction (tan)
- **★ All** — show everything together

Click a pill. The whole app recolors to match. Your choice is remembered between launches.

## Settings

The Settings page has five tabs:

- **Personas** — rename, redescribe, and recolor any of CoC / PoA / Sa. There are five swatches per persona (primary, secondary, tint, accent, text); changing them recolors the whole app instantly.
- **Sites** — add, edit, delete sites. Each site belongs to a persona, has a name, short-code, URL, your username, an optional note, a color, and an optional "login group" (used to mark sites that share the same login — the preloaded OnlyFans rows for CoC and PoA share `of-shared`).
- **Products** — what customers buy from you (Phone, Cam, Customs, Physical merch…). Tagged on customers; will drive sales reports in a later phase.
- **Interests** — what customers like (Feet, Pantyhose, Panties, Humiliation…). Tagged on customers.
- **Backup** — covered below.

Add/edit/delete every list from inside Molly — nothing requires Robert to change code.

## Customers

The **Customers** tab is your little CRM. Each customer has:

- An automatic UID (`YYYY-MM-DD-#####` — resets daily).
- Username, real name.
- Up to five email addresses.
- A persona binding (or no persona for cross-persona contacts).
- Product chips and interest chips (multi-select).
- Rich-text notes — bold, italic, headings, bullet/ordered lists, blockquote, links, horizontal rule.

The list view filters by the active persona (top bar) and supports search across UID / username / real name. Click any customer to open the editor. **Save** only enables when there are unsaved edits. **Delete** is two-tap (click once, confirm within 3 seconds).

## Molly Helper

The **Molly Helper** tab is your one-click site launcher. Each persona gets a row of color-tinted cards showing the site name, short code, your username, and any note. Click **Open** to launch the site in your default browser; click **Copy user** to copy the username to your clipboard. The 🔗 chip shows when a site shares its login with another (use it once for OnlyFans, then switch stores after sign-in).

## Income

Click **Income** in the sidebar. Two tabs:

### 💖 Adhoc income

Where one-off sales go. Add anything — a custom for a fan, a tip on a phone call, a one-time payment. Each entry has a date, amount, persona (or unassigned), source label, and an optional note. The year + month filter at the top lets you backfill any past month (set it to last March for tax prep, etc.).

### 🌐 Site income wizard

Once per month — typically right after the "Income update" reminder fires — open this wizard, pick the month you're entering for, and walk down the list. Sites are grouped by persona; type the dollar amount each site earned for that month. Per-persona subtotals and the grand total update live. You can reopen any past month and edit.

## Expenses

Click **Expenses**. Two tabs:

### 🧾 All expenses

The journal — both your one-off purchases and the materialized rows from recurring expenses live here. Each row has:

- **Actual date** (when the charge hit) and **Effective date** (what month it counts for in reports). Most of the time they're the same.
- Description and note.
- Amount and persona (or unassigned).
- An **attachment** — pick a receipt or invoice; Molly copies it into its own folder so it sticks around even if you move the original. Open / Reveal in Finder / Remove from the editor.
- **Exclude from reports** — fully exclude (personal purchase that doesn't count) or partially exclude (a $100 receipt where $30 was personal: set partial = $30, and reports use $70). The list view shows the gross, net, and excluded totals at the top.

### 🔁 Recurring

Subscriptions and repeating fees. Each entry has a name, amount, persona, anchor date (when it starts), and a cadence (same shapes as the scheduler — Weekly with day mask / Monthly Nth / N days before next month / N days after EOM / Every-N-days / Daily). The "Reads as" + next-5-dates preview match the schedule wizard exactly. Active entries materialize new rows in **All expenses** automatically on app launch + every 30 minutes.

## Reports

Click **Reports**. Three big cards across the top: **MTD** (this month so far), **Prior MTD** (same window in the previous month, for an apples-to-apples comparison), and **YTD**. Each card shows profit, with income and expenses (net of exclusions) underneath.

Below that:
- **Income breakdown (MTD)** — bar chart of Adhoc vs Site income.
- **Site income (YTD)** — per-persona grouped chart of every site's contribution to the year, sized by the site's color.

Click **📄 Export CSV** to write a Year+Month+Persona-stamped CSV next to your other downloads.

## Reminders

Click **Reminders** in the sidebar. The page has two tabs:

### Reminders tab

Four sections, top to bottom:

- **⏰ Overdue** — anything that was due before today and isn't checked off yet. Highlighted in soft red.
- **💖 Today** — what's due today.
- **🌷 Coming up** — the next 7 days.
- **✨ Recently done** — what you've checked off (so you can feel the dopamine).

The little circle on the left of any reminder is the check-off button. Click it once → confetti burst, the item disappears from the list, and a **Undo** toast pops up in the bottom-right for 10 seconds.

### Schedules tab

Five schedules are preloaded, per the original spec:

- *Fan Site Posting — CoC* — monthly, 10 days before next month starts.
- *Fan Site Posting — PoA* — same cadence, PoA.
- *Income update* — monthly, 3 days after the month ends.
- *CoC content release* — weekly, Mondays and Thursdays.
- *PoA content release* — weekly, Wednesdays and Fridays.

You can **Pause** any of them, edit cadence/persona/notes, or delete. Click **✨ New schedule** to add your own. The wizard speaks English, never cron — choose a family (Weekly / Monthly / Every N days / Daily), tweak the specifics, and the "Reads as" line plus "Next 5 dates" preview update live.

The sidebar's 🔔 **Reminders** row shows a red badge with the count of overdue + today items. Click it to jump there.

## Clips & MasterClipper import

Click **Clips** in the sidebar. The list shows everything you've imported, filtered by the active persona, sortable by go-live date / title / status / persona. Search across UID / title / keywords.

To bring in a new export from MasterClipper:

1. In MasterClipper, run an export → CSV.
2. Email/AirDrop/Slack the `.csv` to whichever machine has Molly.
3. In Molly, **Clips → 📂 Import CSV**.
4. Pick the file. You'll see a preview and a small mapping panel: for each persona value found in the file (e.g. `coc`, `poa`), pick the matching Molly persona. Personas not mapped get skipped.
5. Click **Run import**. Re-running the same file is safe — Molly UPSERTs on the MasterClipper UID, so duplicates won't pile up.

Any notes you've added inside Molly (the "Molly notes" field on a clip) are kept across re-imports.

## Calendar

Click **Calendar**. The month grid shows every imported clip on its go-live date as a colored pill (one per persona). Click any pill to open the detail panel; you can read every imported field and write your own rich-text notes that survive future imports. Use **Prev** / **Next** / **Today** to move around.

## Home dashboard

Click **Home**. Four cards: clips this month vs last month, year-to-date, and all-time. Below that, a bar chart of clips per persona, a **reuse detection** panel that flags possible duplicate posts (same external ID, or same title within ~2 weeks), and a recent-imports log.

## The sidebar

The icons down the left side are the main feature areas. Click any one to jump there. Press **Ctrl+S** (Windows) or **⌘+S** (Mac) to hide / show the sidebar.

## Settings → Backup

This is the most important thing to know about right now. Molly automatically saves a zip of all your data **every time you open it** (with a 5-minute breather between runs so debugging doesn't fill your downloads folder).

### Where backups live by default

- **Mac**: `~/Downloads/Molly backup/`
- **Windows**: `%USERPROFILE%\Downloads\Molly backup\`

The folder is created the first time it's needed.

### What's in Settings → Backup

- **Auto-backup on launch** — leave this on.
- **Backup folder** — change where backups land. Click **Choose…** to pick. Click **Default** to reset.
- **Retention (days)** — Molly deletes backups older than this. Default 14 days. Set `0` to keep forever. Only Molly's own backup files are deleted; anything else in that folder is left alone.
- **Run Backup Now** — make a backup right now (ignores the 5-minute debounce).
- **Reveal in Finder / Explorer** — open the backup folder.
- **Recent backups list** — every backup with three buttons each:
  - **Test** — checks that the backup is valid and the database is inside. Safe to click any time.
  - **Restore** — DANGER. Replaces all your current Molly data with the contents of this backup. Molly always saves a "pre-restore" safety backup first, so if you click Restore by accident, you can Restore the safety one to undo.
  - **Reveal** — show the .zip in Finder / Explorer.

### Sending a backup to Robert

If Robert asks for a copy of your data:

1. Settings → Backup → **Run Backup Now**.
2. Find the new zip in the backup folder (newest at the top of the list).
3. Drag it into our Slack DM.

That's it. He'll import it on his side to look at what's going on.

## Sending Robert a copy of your data

Open **Settings → Data**, then **📦 Export everything**. Molly zips its whole brain — database, every receipt you've attached, your settings, plus a small manifest — into a single file in `~/Downloads/Molly export/` (Mac) or `%USERPROFILE%\Downloads\Molly export\` (Windows). The screen shows where the file landed; click **Reveal in Finder** to find it.

Drop that .zip into our Slack DM. Robert will import it on his dev machine and see exactly what you see.

Re-exporting just adds a fresh file next to the older ones. Nothing is overwritten or deleted.

## Updating Molly

When a new version is ready, Molly checks for it on launch and tells you. You'll see a banner with a **Download update** button. Click it, then close and reopen Molly. The new version installs in place — your data is untouched.

If the banner ever fails, you can always download the latest installer from the [GitHub Releases page](https://github.com/bronty13/PhantomLives/releases) and run it.

## Where Molly stores its actual data

- **Mac**: `~/Library/Application Support/Molly/`
- **Windows**: `%APPDATA%\com.phantomlives.molly\`

You shouldn't ever need to touch this folder — backups handle it. But if your computer is migrating to a new machine, copy this directory to the new machine in the same location and Molly will pick up where it left off.
