# Molly — Your Little Manual 💕

Hi Sallie 💖

This is your very own guide to using Molly — written for **you**, not for engineers, not for anyone else. Think of it like a cozy chat over coffee about how your new tool works. Take it at your own pace; skip around; come back whenever something feels confusing. Nothing here is permanent — if anything is unclear, screenshot it and send it my way in Slack and Robert will smooth it out.

> ✨ You're on **Molly v1.8** — the C4S Store has joined the family. Every saying in the app, every cute font, every pastel card is here because somebody (👋) thought you'd like it. If you ever want me to change anything — color, wording, anything — just say the word.

---

## 🌷 Your little inspiration

The pastel card at the top of the **Home** page (and the tiny saying tucked under "Molly" in the sidebar) rotates through 1,000 hand-picked encouragements — picked just for you. Click **✨ another** on the big card, or click the saying itself in the sidebar, to roll a new one. Even the **font** shuffles each time, swirling through ten cute display fonts. You'll never see the same combo twice in a row.

This is supposed to be your soft place. Use it that way.

---

## 💌 Opening Molly

### macOS

Double-click **Molly** in your Applications folder, or hit `⌘+Space` and type "Molly". She'll come to you. 🌸

### Windows

Double-click the **Molly** icon on your Desktop or Start menu.

If Windows SmartScreen ever says *"Windows protected your PC"*, just click **More info** → **Run anyway** the first time. The installer is signed by Robert — SmartScreen just hasn't seen many users yet. After the first time, it'll stop asking.

---

## 🎀 The persona switcher

The little pills at the top right are your three personas plus an "everything" view:

- **CoC** — Curse Of Curves (baby pink) 🌸
- **PoA** — Princess of Addiction (red & black) ❤️🖤
- **Sa**  — Sheer Attraction (warm tan) 🌾
- **★ All** — show every persona at once

Click a pill and the **whole app recolors** to match. It's not just decoration — every list, dashboard, and filter scopes to whichever persona is active. Your last choice is remembered between launches, so Molly opens in your favorite color the next morning.

> 💡 Tip: when you want to compare CoC vs PoA side by side, click **★ All** and the dashboards interleave both stores at once.

---

## ⚙️ Settings — making Molly *yours*

The Settings page has tabs across the top. Nothing here requires Robert to change code — it's all yours to play with.

- **👯‍♀️ Personas** — rename, redescribe, and recolor any of CoC / PoA / Sa. Five swatches per persona (primary, secondary, tint, accent, text); changing them recolors the whole app instantly. Want a different shade of pink? Try it. Don't like it? Click again.
- **💻 Sites** — add, edit, delete sites. Each one belongs to a persona, with a name, short code, URL, your username, an optional note, a color, and an optional "login group" (used for shared-login families like OnlyFans CoC ↔ PoA).
- **📦 Products** — what your fans buy from you (Phone, Cam, Customs, Physical merch…). Each product carries a price + unit (e.g. *Customs at $5.00 / minute*, *Physical Panties at $25.00 / item*). Used for sales tracking and tagging on customer cards.
- **🌷 Interests** — what your customers like (Feet, Pantyhose, Panties, Humiliation…). Multi-select tags on each customer.
- **💕 Kinks** — what they're into. Ships with ~350 curated entries, each with a short definition. Rename, recolor, archive, or delete any of them — they're just regular taxonomy rows. The real magic happens on the customer card (see below).
- **🛍️ C4S** — toggles for the C4S Store view (stale-data banner, which columns to show, import button, delete-all). See the C4S section below.
- **📦 Data** — full-data export (covered below).
- **⬇️ Updates** — check for and install new Molly versions.
- **💾 Backup** — the safety net. *Important — read this section below.*

---

## 👯‍♀️ Customers — your little CRM

The **Customers** tab is where every fan and customer lives. Each customer has:

- An automatic UID (format `YYYY-MM-DD-#####` — resets daily). You don't have to type it.
- **Username** and **real name**.
- Up to **five email addresses**, with a radio button on each so you can mark one as primary.
- A **persona binding** (or no persona for cross-persona contacts).
- **Product chips** + **interest chips** (multi-select; click to toggle).
- A **Kinks picker** — click **+ Add kink** to open a searchable dropdown of the 350-row catalog. Type to filter; click a row to add it as a numbered chip. To create a kink that doesn't exist yet, type its full name and press Enter — a "Create kink: '…'" row appears at the top. Each chip has an × to remove. Order is preserved per customer — drag chips to reorder.
- **⭐ VIP toggle** — click the `☆ VIP` pill in the header to mark a customer as VIP. VIPs sort to the top of the customer list and pick up a ⭐ chip on their row.
- **Mailing address** — full address (line 1, line 2, city, state/province, zip + +4, country). Country defaults to US; the dropdown carries the full international list with US / CA / GB pinned to the top.
- **Two phone numbers** — each with a 📱 Mobile checkbox and a shared "primary phone" radio. US numbers format-as-you-type into `(XXX) XXX-XXXX` and show a soft amber warning under any that aren't complete yet.

### 📜 History & sales

Below the main Notes section, every customer has a combined **History & sales** card. Two kinds of entries live together here, newest-first:

- **📝 Notes** — timestamped notes with optional file attachments. Type in the composer, click **📎 Attach file…** if you want, then **➕ Add note**. Attachments are stored inside Molly's database (so they travel with backups and exports). Click the **📎 filename** chip on any past entry to save the attached file back out to disk. Each note has **Edit** / **Delete** buttons — editing reveals an inline textarea (Save / Cancel); deleting is two-tap confirmed and removes the row plus any attached file.
- **🛒 Sales** — click **🛒 + Add sale** to record a transaction. Pick the product, enter quantity (e.g. `10` for 10 minutes), the unit price defaults from the product but you can override it, and the total auto-computes. Editing the total back-solves the unit price for line-level discounts. Add notes describing what was sold. Sales are fully editable + deletable. The customer's **lifetime sales total** appears as a `💖 $X.XX` pill in the editor header (hidden when zero). Sales also automatically appear in **Income → Adhoc income** (marked 🛒) and roll into the MTD / YTD totals on Reports + Home.

The timeline interleaves notes + sales together, newest first.

**Filter the timeline** with the search box above the list — filters by note text, attachment filename, sale notes, and product name. Substring match by default; tick the **regex** checkbox for a real regular expression. Invalid regex shows a soft amber warning; valid filters show *"N of M"* + a Clear button while active.

The list view filters by the active persona (top bar) and supports search across UID / username / real name / primary email — substring or regex (with the same checkbox). Click any customer to open the editor. Edits **auto-save** ~800ms after you stop typing — there's a "💾 Saving…" / "✏️ Unsaved — auto-saving…" / "✓ Saved" status next to the explicit **💾 Save now** button. The ← Back button also flushes any pending changes before closing. **Delete** is two-tap (click once, confirm within 3 seconds).

---

## 📣 Promos — where your hustle gets logged

Click **📣 Promos** in the sidebar. This is where every Reddit thread, X post, IG story, and TikTok video you put up to drive traffic gets recorded.

Click **✨ New promo** to add one. Fields:

- **Persona** — which version of you is posting.
- **Platform** — Reddit / X / Instagram / TikTok come preloaded; add more in Settings → Platforms.
- **Handle** — your username on that platform (`u/coc`, `@curse_of_curves`, etc.).
- **Posted at** — local date + time picker.
- **URL** — link to the post. Use **Open** in the list view to launch it later.
- **Title** + **body** — what you actually posted.
- **Linked clip** (optional) — pick from a dropdown of recent clips for the active persona.
- **Notes** — rich-text. Jot down what hashtags worked, the time of day, comments that came in.

The list filters by platform, year, month, and free-text search across title / handle / body. The active persona at the top further narrows things.

The **Reports** page has a Promos section: MTD + YTD post counts and a per-platform bar chart sized by platform color. Watch where your traction is coming from.

---

## 💅 Molly Helper — one-click site launcher

The **Molly Helper** tab is your shortcut row. Each persona gets a row of color-tinted cards showing the site name, short code, your saved username, and any note. Click **Open** to launch the site in your browser; click **Copy user** to drop the username on your clipboard. The 🔗 chip appears when a site shares its login with another (use it once for OnlyFans, then switch stores after sign-in).

---

## 💖 Income

Click **Income** in the sidebar. Three tabs across the top:

### 💖 Adhoc income

Where one-off sales go. Add anything — a custom for a fan, a tip on a phone call, a one-time payment. Each entry has a date, amount, persona (or unassigned), source label, and an optional note. The year + month filter at the top lets you backfill any past month (set it to last March for tax prep, etc.). Sales from the Customer timeline appear here too, marked 🛒.

### 🌐 Site income wizard

Once a month — typically right after the *"Income update"* reminder fires — open this wizard, pick the month, and walk down the list. Sites are grouped by persona; type the dollar amount each site earned for that month. Per-persona subtotals + grand total update live. You can reopen any past month and edit at any time.

### 📊 Sales report import

For sites that give you a CSV of every sale (Clips4Sale, IWantClips, etc.) — pick the site at the top, choose the CSV, and Molly figures out which column is the date and which is the amount, then totals by month. You'll see a preview with: rows found, the CSV total, what was already in Molly for that month, and what it'll become after import. Pick **Replace** (overwrite the month's value) or **Add** (sum into the existing value). Click **Run import**.

If any rows can't be parsed, the importer lists them at the bottom so nothing is silently lost.

---

## 🧾 Expenses

Click **Expenses**. Two tabs:

### 🧾 All expenses

The journal — both your one-off purchases and the materialized rows from recurring expenses live here. Each row has:

- **Actual date** (when the charge hit) and **Effective date** (what month it counts for in reports). Usually the same.
- **Description** and **note**.
- **Amount** and **persona** (or unassigned).
- An **attachment** — pick a receipt or invoice; Molly copies it into its own folder so it sticks around even if you move or rename the original. Open / Reveal in Finder / Remove from the editor.
- **Exclude from reports** — fully exclude (personal purchase that doesn't count) or partially exclude (a $100 receipt where $30 was personal: set partial = $30, and reports use $70). The list view shows the gross, net, and excluded totals at the top.

### 🔁 Recurring

Subscriptions and repeating fees. Each entry has a name, amount, persona, anchor date (when it starts), and a cadence — Weekly with day mask / Monthly Nth / N days before next month / N days after EOM / Every-N-days / Daily. The "Reads as" line + next-5-dates preview update live so you can see exactly when things will fire. Active entries auto-materialize new rows in **All expenses** on app launch + every 30 minutes — you don't have to do anything.

---

## 📊 Reports

Click **Reports**. Three big cards across the top:

- **MTD** — this month so far.
- **Prior MTD** — same window in the previous month (for an apples-to-apples compare).
- **YTD** — year-to-date.

Each card shows profit, with income and expenses (net of exclusions) underneath.

Below that:

- **Income breakdown (MTD)** — bar chart of Adhoc vs Site income.
- **Site income (YTD)** — per-persona grouped chart of every site's contribution to the year, sized by the site's color.
- **Promos** — MTD + YTD post counts per platform.

Click **📄 Export CSV** to write a Year+Month+Persona-stamped CSV next to your other downloads. Hand it to your accountant; they'll love you.

---

## 🔔 Reminders

Click **Reminders** in the sidebar. The page has two tabs.

### Reminders tab

Four sections, top to bottom:

- **⏰ Overdue** — anything due before today that isn't checked off yet. Highlighted in soft red.
- **💖 Today** — what's due today.
- **🌷 Coming up** — the next 7 days.
- **✨ Recently done** — what you've checked off (so you can feel the little hit of dopamine).

The little circle on the left of any reminder is the check-off button. Click it once → 🎉 confetti burst, the item disappears from the list, and an **Undo** toast pops up in the bottom-right for 10 seconds.

### Schedules tab

Five schedules come preloaded:

- *Fan Site Posting — CoC* — monthly, 10 days before next month starts.
- *Fan Site Posting — PoA* — same cadence, PoA.
- *Income update* — monthly, 3 days after the month ends.
- *CoC content release* — weekly, Mondays + Thursdays.
- *PoA content release* — weekly, Wednesdays + Fridays.

You can **Pause** any of them, edit their cadence / persona / notes, or delete. Click **✨ New schedule** to add your own. The wizard speaks **English**, never cron — choose a family (Weekly / Monthly / Every N days / Daily), tweak the specifics, and the *"Reads as"* line + next-5-dates preview update as you type.

The sidebar's 🔔 **Reminders** row shows a red badge with the count of overdue + today items. Click it to jump straight there.

---

## 🎬 Clips & MasterClipper import

Click **Clips** in the sidebar. The list shows everything you've imported, filtered by the active persona, sortable by go-live date / title / status / persona. Search across UID / title — substring or regex.

To bring in a new export from MasterClipper:

1. In MasterClipper, run an export → CSV.
2. Email / AirDrop / Slack the `.csv` to whichever machine has Molly.
3. In Molly, **Clips → 📂 Import CSV**.
4. Pick the file. You'll see a preview and a small mapping panel: for each persona value found in the file (e.g. `coc`, `poa`), pick the matching Molly persona. Personas you don't map get skipped.
5. Click **Run import**. Re-running the same file is safe — Molly UPSERTs on the MasterClipper UID, so duplicates won't pile up.

Any notes you've added inside Molly (the *"Molly notes"* field on a clip) are kept across re-imports. Promise. 💕

---

## 🛍️ C4S Store — your live Clips4Sale catalog

Click **🛍️ C4S Store** in the sidebar. This is your read-only window into what's *actually* live on Clips4Sale right now — both stores, side by side. Molly never writes to C4S; she just reads what's there.

### 📥 Refreshing the snapshot

C4S lets you export every clip in your store as a CSV. Do it for each store separately:

1. In C4S, go to your store's clip list → click **Export CSV** at the bottom. Save the file to your Downloads folder. It'll be named something like `coc_clips-export-2026-05-21_21-35-11.csv` or `poa_clips-export-2026-05-21_21-34-43.csv`.
2. Back in Molly, click **✨ Import C4S CSV** (top right of the C4S dashboard, or in Settings → 🛍️ C4S).
3. Pick the file. Molly reads the **Performers** column to guess which store it is — when she says *"Looks like a CoC export"* (or PoA), click the highlighted button. If the guess is wrong, click the other store instead.
4. The import replaces *all* of that store's data in one go. The other store is untouched. Molly verifies the row count after import — you'll see a ✓ if the count matches what was parsed. Anything weird gets surfaced in a little expandable list so nothing fails silently.

You can re-import as often as you want — each run overwrites the prior snapshot.

### 🌸 The dashboard

The **freshness banner** at the top shifts language based on how old your snapshot is:

- 🌸 **Fresh from C4S — just imported!** (today)
- ✨ **X days old — still pretty fresh** (1 week)
- 🌷 **X days old — might be worth a re-import soon** (up to a month)
- 🌼 **X days old — time for a fresh export?** (older)
- 🌱 **No C4S data yet — drop your latest export to get started!** (never imported)

The font even shuffles each time you visit. 💕 Hide the banner entirely from Settings → 🛍️ C4S if you'd rather not be reminded.

Below the banner:

- **Total clips, lifetime sales, income (last 6 months)** — three big numbers.
- **By store** (when ★ All is active) — per-store bar showing how the count splits between CoC and PoA.
- **Clips by status** — bars per status (`active`, `p7_under_review`, `draft`, etc).
- **Top 10 categories** and **Top 10 keywords** — what you lean on most. Sometimes surprising. ✨
- **Pricing** — min / mean / max price across your live clips.

### 🗂 The grid

Click **🗂 Grid** at the top of the C4S page to switch to a sortable table. Search bar with a **regex** checkbox. Click any column header to sort; click again to flip direction. The **Status** dropdown filters to one status at a time. Click any row to dive into the **detail page** — full description in handwriting font, all 14 C4S fields laid out, with **📋 Copy title** + **📋 Copy ID** buttons up top. Click **← Back** to return to the grid with your search/sort/filter still in place.

### Settings → 🛍️ C4S

- **Show stale-data banner** — toggle the cute freshness banner (default on).
- **Visible columns** — choose which columns appear in the grid. **Persona** and **Title** always show; everything else is optional. **Tracking Tag** and **Preview Filename** default off because C4S exports always leave them empty.
- **✨ Import C4S CSV** — same wizard as the dashboard.
- **🗑 Delete all C4S data** — wipes both stores' snapshots (two-tap confirm). Your MasterClipper clips, customers, expenses, etc. are not affected.

---

## 🎁 Bundles — packages for Robert

Click **🎁 Bundles** in the sidebar. This is where you compose a delivery package for Robert — everything he needs to post-produce one piece of content, zipped and ready to drop into Slack.

There are three flavors planned:

- **Content Bundle** (live now) — a single piece of content with title, persona, description, categories, files, go-live date, and special instructions.
- **Custom Bundle** (next release) — a custom video for a specific platform / user / price.
- **Fan Site Bundle** (next release) — a whole month's worth of fan-site posts on a calendar.

### Creating a Content Bundle

Click **＋ New Content Bundle**. Molly creates an empty draft with a UID like `2026-05-22-0001` and drops you into the form. Everything you type saves on blur — close the tab and come back, your draft is still there.

What to fill in:

- **Persona** — required. CoC, PoA, or Sa.
- **Title** — at least two words. (Sweet little safeguards: blank, `none`, `blank`, `custom`, or a single word all get gently rejected.)
- **Description** — pick **📝 Type** to write text, or **🎙️ Upload audio** to attach a voice note. Exactly one is required. Text gets scanned live for prohibited words (defaults: `blackmail`, `mommy`, `addiction`, `addicted` — editable in Settings → Bundler).
- **Categories** — at least three. Type to filter / create; drag the chips to reorder. They save UPPERCASE. Past categories from any bundle show as suggestions.
- **Go-live date** — required, no past dates. If today or within 5 days, Molly gently asks *"Are you allowing enough time for editing?"*.
- **Files** — at least one video or image. Drag rows to reorder. Each file is renamed `00001_…` in the final ZIP so Robert can rely on the order.
- **Special instructions** — optional free-text for Robert.

### Publishing

When you're ready, click **🎁 Review & Publish…**. A wizard slides in from the right with every field rendered read-only — you can play the audio, scroll through image thumbnails, see categories in their final order. The **Pre-flight checks** section lists anything still missing; click any issue to jump straight to the field that needs love.

When everything's green, click **✨ Approve & Publish**. Molly:

1. Hashes every file (re-reads from disk; refuses if anything's changed since upload).
2. Writes an inner ZIP with `info.md`, `Molly.log`, plus `Audio/`, `Video/`, `Photos/` folders.
3. Wraps that inner ZIP plus `hashes.json` into an outer ZIP at `~/Downloads/Molly bundles/<UID>.zip`.
4. Creates (or updates) a row in **Clips** with status `Bundled` so the go-live date shows on your Calendar.

The success card gives you **Open ZIP** and **Reveal in Finder** buttons, plus both SHA-256 digests in case Robert wants to verify.

### Editing after publish

A published bundle is locked — the form goes read-only. If you need to change something, click **Delete bundle** on the list row (or on the published draft). That removes the ZIP from disk and flips the bundle back to draft state so you can edit and re-publish. **Your linked Clip row survives** — Sallie's `molly_notes_html` is preserved across re-publishes.

### Settings → 🎁 Bundler

- **Output folder** — default `~/Downloads/Molly bundles/`. Override + Reveal.
- **Warn threshold (days)** — drafts older than this get a soft 🌷 / 🌼 badge on the list.
- **Auto-purge threshold (days)** — published bundles older than this get their ZIP removed (the bundle row stays as `purged` for history). Runs once per day at launch; **Run purge now** bypasses the debounce.
- **Auto-purge enabled** — separate toggle from the threshold, so you can flip-test without losing your number.
- **Prohibited words** — chip list. Add / remove any time.

---

## 📔 Molly's Log — your personal journal

Click **📔 Molly's Log** in the sidebar. This is your private journal — append timestamped notes to yourself about whatever (today's mood, end-of-day reflection, an idea you don't want to forget). Optional file attachment per entry — image, PDF, anything. Stored inside Molly's database, so attachments travel with your auto-backup zips.

Past entries render in a **handwritten font (Caveat)** for that journal-page feel; the composer stays in the regular UI font so typing is crisp.

- **✨ Log entry** — type into the composer and click the button. Attach a file via **📎 Attach file…** first if you want one saved with this entry.
- **Edit / Delete** — each past entry has Edit + Delete buttons. Edit reveals an inline textarea (Save / Cancel); Delete is two-tap-confirmed and removes the row plus any attached file.
- **Filter** the list with the search box; tick **grep** for regex mode. Searches across the entry body + attachment filename. Shows *"N of M"* while filtering.

Use it however you want. Nobody reads it but you. 💕

---

## 📅 Calendar

Click **Calendar**. The month grid shows every imported clip on its go-live date as a colored pill (one per persona), and every pending reminder on its due date as a 🔔 pill with a dashed border (color-matched to the schedule's persona, or neutral when the schedule isn't bound to one). Completed reminders drop off automatically. Click any clip pill to open its detail panel — read every imported field and write your own rich-text notes that survive future imports. Use **Prev** / **Next** / **Today** to move around.

---

## 🏠 Home dashboard

Click **🏠 Home**. The very first thing you'll see is the **cute saying card** — a different one every render, in a different font. ✨ Below that, today's reminders (if any), then four count cards (this month vs last, year-to-date, all-time), a bar chart of clips per persona, a **reuse detection** panel that flags possible duplicate posts (same external ID, or same title within ~2 weeks), and a recent-imports log.

The Home page is your morning landing pad. Look at it once with coffee. 🌷

---

## 🧭 The sidebar

The icons down the left side are the main feature areas. Click any one to jump there. Press **Ctrl+S** (Windows) or **⌘+S** (Mac) to hide / show the sidebar — great when you want more room for the C4S grid or the Customers list.

The little saying under "Molly" at the top of the sidebar is **clickable** — click it to re-roll. 💕

---

## 💾 Backup — your safety net

This is the most important section. **Read this once and you can forget about it.**

Molly automatically saves a **zip of all your data every time you open the app** (with a 5-minute breather between runs so debugging doesn't fill your Downloads folder). The auto-backup is on by default. Don't turn it off.

### 🗂 Where backups live by default

- **Mac**: `~/Downloads/Molly backup/`
- **Windows**: `%USERPROFILE%\Downloads\Molly backup\`

The folder is created the first time it's needed.

### What's in Settings → 💾 Backup

- **Auto-backup on launch** — leave this on. 💕
- **Backup folder** — change where backups land. Click **Choose…** to pick a new spot. Click **Default** to reset to the convention path.
- **Retention (days)** — Molly deletes her own backups older than this. Default 14 days. Set `0` to keep forever. *Only Molly's own backup files are touched* — anything else in that folder is left alone.
- **Run Backup Now** — make a backup right now (ignores the 5-minute debounce).
- **Reveal in Finder / Explorer** — open the backup folder.
- **Recent backups list** — every backup, newest at the top, with three buttons each:
  - **Test** — checks that the backup is valid + that the database is inside. Safe to click any time.
  - **Restore** — ⚠ DANGER. Replaces all your current Molly data with the contents of this backup. **Molly always saves a "pre-restore" safety backup first**, so if you click Restore by accident, you can Restore the safety one to undo. Don't panic.
  - **Reveal** — show the .zip in Finder / Explorer.

### 💌 Sending a backup to Robert

If Robert asks for a copy of your data so he can debug something:

1. **Settings → 💾 Backup → Run Backup Now**.
2. Find the new zip in the backup folder (it's at the top of the Recent backups list).
3. Drag it into our Slack DM.

That's it. He'll import it on his machine and see exactly what you see. 💕

---

## 📦 Sending Robert your whole brain

Open **Settings → 📦 Data**, then click **📦 Export everything**. Molly zips her entire brain — database, every receipt you've attached, your settings, plus a small manifest — into a single file under `~/Downloads/Molly export/` (Mac) or `%USERPROFILE%\Downloads\Molly export\` (Windows). The screen shows where the file landed; click **Reveal in Finder** to find it.

Drop that .zip into our Slack DM. Re-exporting just adds a fresh file next to the older ones — nothing is overwritten or deleted. ✨

---

## ⬇️ Updating Molly

When a new version is ready, Molly checks for it on launch and tells you. You'll see a banner with a **Download update** button. Click it, then close and reopen Molly. The new version installs in place — **your data is untouched**.

If the banner ever fails, you can always download the latest installer from the [GitHub Releases page](https://github.com/bronty13/PhantomLives/releases) and run it.

---

## 🗄 Where Molly stores her actual data

- **Mac**: `~/Library/Application Support/com.phantomlives.molly/`
- **Windows**: `%APPDATA%\com.phantomlives.molly\`

You shouldn't ever need to touch this folder — backups handle everything. But if your computer is migrating to a new machine, copy this directory over (same location on the new side) and Molly will pick up exactly where she left off.

---

## 💕 A note from the team

Molly was built **for you**. Every cute font, every soft color, every saying, every little 💕 — it's all here because we wanted something that felt like a friend, not a spreadsheet. If anything feels off, awkward, or unfriendly, **tell Robert**. He'll fix it. Always.

You're doing the work — Molly's just trying to make it a little softer. 🌷

Go make something pretty. ✨
