# What's new in Molly 💕 — v1.10

Hi Sallie 💖

A small but mighty update — the **🎁 Bundles** tab is now *complete*. You already had Content bundles working in v1.9; this release brings the two missing bundle types online so the whole feature is one happy little package.

Everything you've been doing in Content bundles still works exactly the same. These are *additions*.

---

## ✨ Custom Bundles — for one-off custom videos

Click **🎁 Bundles → ＋ New Custom Bundle**. Same gentle form as Content, but tailored for *"this is a custom I made for one specific person on one specific platform"*:

- **Persona + Title + Files + Special Instructions** — same as Content.
- **Go-live date** — defaults to tomorrow (customs tend to be quick turnarounds).
- **Delivery platform** — pick **🌐 Site** to choose from the sites you've already added in Settings → Sites (Molly auto-filters to your bundle's persona), OR **🔗 URL link** to paste any URL. One or the other, not both. URLs have to start with `http://` or `https://`.
- **Recipient** — who's this for? Free-text — a username, a real name, however you and Robert refer to the buyer.
- **Price** — money field. Or tick **handled in delivery platform** if the platform's already collecting the money and you don't need to track it again.

No description, no categories — those are Content-bundle things. Publish wraps it all into the same SHA-256-hashed ZIP at `~/Downloads/Molly bundles/`.

---

## 📅 Fan Site Bundles — a whole month, on a calendar

This is the big one. Click **🎁 Bundles → ＋ New Fan Site Bundle** when you want to bundle up an entire month of fan-site posts in one go.

1. Pick the **year + month** you're planning for.
2. Molly draws the whole month as a 7-column calendar (Sunday-Saturday at the top). Every day is a clickable cell.
3. Click any day → a panel slides in from the right with:
   - a **short message** textarea (the caption / tease for that day's post)
   - a **file picker** (videos and images, drag to reorder — files are scoped to that day)
   - a **🗑 Delete day** button if you want to clear it and start over
4. Close the panel, click the next day, repeat. Save anytime; partial progress sticks around forever until you bundle (or delete) the draft.

### The calendar colors itself in as you go ✨

- **white** — empty (no message, no files yet)
- **amber 🌼** with `…` — partial (has one or the other, not both)
- **persona-accent** with `✓` — complete (message + ≥1 file)

There's a **completion bar** under the calendar showing `X/N complete · M partial` and filling up. The bundle becomes publishable when every day in the month is complete — Molly's pre-flight checklist will tell you exactly which days still need love, with click-to-jump buttons that scroll you straight to the right cell.

### How the files get named in the ZIP

`FanSite/01_01_<original-name>`, `FanSite/01_02_…`, `FanSite/15_01_…`, etc. The first number is the calendar day (zero-padded), the second is the within-day order. So Robert can rely on both the date *and* the order you intended for each day.

---

## 🌷 Everything else stays the same

Your customers, kinks, products, sales, expenses, reminders, schedules, calendar, Molly's Log, MasterClipper clips, C4S Store, promos, reports, backups, the Content Bundle flow — all unchanged. Auto-backup on every launch is still humming.

---

You're doing the work. Molly is just trying to make the *delivery* part — *all* of it now — a little softer. If anything feels off — colors, wording, the calendar layout, validation strictness, defaults — just tell Robert in Slack.

Go make something pretty. ✨💕

— Molly, your soft little helper

*(v1.10.0, posted 2026-05-22)*
