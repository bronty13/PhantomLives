# CalendarMaker — User Manual

CalendarMaker makes beautiful, printable monthly calendars. It runs entirely in
your web browser, with no internet needed.

## Getting started

1. Unzip `CalendarMaker-app.zip`.
2. Double-click `index.html` — it opens in your browser.
3. (Optional) In your browser settings, set the **download folder** to
   `~/Downloads/CalendarMaker/` so your exported PDFs land together.

## The home screen

- A **greeting** at the top says "Good morning/afternoon/evening, <your name>".
  Set your name in **Settings** (it defaults to *Jan*).
- A **verse of the moment** and **a little encouragement** (a saying) appear
  below it, each in its own pretty style. Click **↻** to see another. You can turn
  either off in **Settings**.
- Below them is **Your calendars** — every calendar you've made.

## Making a calendar

1. Click **+ New calendar**.
2. Enter a **Title** — this is the saved name (e.g. "Grace Church — June 2026").
3. Choose the **Month & year**. It defaults to *next month*; use the dropdown and
   the −/+ year buttons to pick any month, past or future.
4. Pick a **Theme** (you can change it later).
5. Click **Create** — the calendar editor opens.

## Adding events to a day

1. **Click a day** on the calendar.
2. In the panel, choose a **type** (Prayer, Praise, Birthday, Life Event, Church
   Event, Reminder, **Bible Verse**, **Saying**), type the text, and click
   **+ Add item**.
3. Add as many as you like. Edit text or change a type anytime; click ✕ to delete.

### Bible verses & sayings on a day

When you pick the **Bible Verse** type, a fast picker appears. Two ways to find
your verse:

- **Type it** — start typing a reference in the box: `John 3:16`, `Phil 4:13`,
  even `1 Jo 5 4`. Press **Enter** to grab it. Typing just a name (e.g. `phil`)
  narrows the book grid (Philippians / Philemon).
- **Tap it** — tap a **book** (grouped Old / New Testament; shown as compact
  3-letter abbreviations like `Gen`, `1Sa`, `Phi` — hover to see the full name),
  then a **chapter**, then a **verse**. The breadcrumb at the top (Book › Chapter
  › Verse) lets you step back a level anytime.

Pick the **Saying** type to get a searchable list of every built-in and custom
saying (or hit **↻ Random**). Existing verse/saying items show a small reference
tag (e.g. *John 3:16*); click **✎ Edit** to reopen the picker. A day can hold both
a verse and a saying (and as many as you like).

#### Two ways verses & sayings appear — the "Verse Mode" toggle

In the toolbar, **Verse Mode** switches how these items print:

- **Separate** *(default)* — verses and sayings are kept **off** the main month
  grid and printed on their own landscape **"Scripture & Sayings"** calendar
  page. Your everyday events stay uncluttered, and scripture gets a beautiful
  page of its own.
- **Force** — verses and sayings are **plastered at the top of each day cell**
  (shrunk to fit), and the little colored dots are hidden for a clean look. Other
  events still show underneath if there's room.

### When something won't fit

The month grid stays clean no matter what:

- If a day has more items than fit, you'll see an alert. The extra items are
  **saved** and will print in the **Detail view**, marked with a ⊘ in a
  different color.
- To choose which items appear on the **month grid**, tick **Pin to month** on
  the ones you want. The rest become detail-only.
- A very long item that can't fit a cell at all is automatically detail-only
  (labeled "too long").

## Holidays

Click **Holidays** in the toolbar. Every holiday that falls in your month is
listed (federal, observances, and Christian days like Good Friday and Easter).
Click **Off/On** to place each one on your calendar.

## Sayings & verses (whole-month filler)

This is separate from per-day verses (above) — it decorates the calendar's empty
space with a single saying or verse for the whole month. Click **Sayings &
Verses**:

- **Where**: the **footer band** (below the grid) or the **grid free space**
  (empty day cells).
- **What**: a **Bible verse** (Random, or pick a book / chapter / verse) or a
  **Saying** (click ↻ for another).
- Click **Place…**. Remove a placement anytime from the same panel.

## Themes

Click **Themes** to switch the look, or to **Duplicate** a built-in theme and
**Edit** your copy — set the font and color for each item type, plus the title,
header, holiday, saying, and background colors. Delete your custom themes when
done. Built-in themes can't be edited or deleted (duplicate them instead).

## Exporting to PDF

Click **Export PDF**, then choose:

- **Month view** — the printable calendar grid (landscape).
- **Detail view** — a date-ordered list of every day and its events (portrait).
- **Both** — month grid first, then the detail list, in one PDF.

If you've added per-day verses/sayings in **Separate** mode, a **Scripture &
Sayings** calendar page is included automatically (whenever the month is part of
the export). For **Both**, you can choose the page order: *Calendar → Scripture →
Detail* (default) or *Calendar → Detail → Scripture*.

Click **Export PDF** to download. You can also **Export bundle (.cmcal.json)** to
back up the calendar or move it to another computer (use **Import…** on the home
screen to bring it back).

## Settings

- **Your name** — used in the home-screen greeting (default *Jan*).
- Default theme, week start (Sun/Mon), and default export view for new calendars.
- The safety cap for how many items show per day on the month grid.
- Toggles for the home-screen verse and saying cards.
- **Custom sayings** — manage your own sayings inline. Click **+ Add new saying**
  to enter text and an optional attribution; click any saying's **✎** to edit it
  in place, or **✕** to delete it. Everything saves right away and joins the pool
  used by the home card, the day-level Saying picker, and the whole-month filler.
  Expand **Built-in Sayings** to browse the seeded ones (they can't be edited or
  removed).

## Where is my data?

Calendars are saved in your browser on this computer. To move them or keep a
backup, use **Export bundle (.cmcal.json)** and **Import…**.
