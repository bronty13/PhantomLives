# What's new in Molly 💕 — v1.13

Hi Sallie 💖

This is the big one. Three releases (1.11, 1.12, 1.13) all landing together — and they're all about **keeping your passwords safe** and **letting Molly do the boring stuff for you while you sleep**.

Nothing you've been doing before changes. Customers, kinks, products, sales, expenses, reminders, schedules, calendar, Molly's Log, MasterClipper clips, C4S Store, promos, reports, Bundles, backups — all exactly the same. These are *additions*. 🌷

---

## 🔐 First: a little safety deposit box (Settings → 🔐 Security)

Before any of the new stuff works, Molly needs you to set up a **passphrase** — just one, ever. Settings → 🔐 Security → **Set a passphrase**. Pick something you'll remember (a short sentence is great: `purple sparkles in the kitchen` is way better than `P@ss1`).

That passphrase locks a "safe deposit box" inside Molly. Everything sensitive — site passwords, your ATW login — gets locked into the box. The box is locked at every app launch, and auto-locks itself after **8 hours** of you being away. There's also a **🔒 Lock now** button if you want to slam it shut yourself.

### Your recovery words (this is the magic part)

After you set the passphrase, click **Reveal recovery words** and Molly shows you **24 little words** — written down in a nice 6×4 grid:

```
1. apple      2. bridge     3. canyon     4. dragon     5. envelope   6. flute
7. garden     ... etc
```

These 24 words **ARE the key to everything**. Write them on paper. Put the paper somewhere safe. Robert will probably want a copy too — send them to him in Slack DM if you want, or whatever feels right.

**Why this matters**: when Robert sets up Molly on *his* Mac, he just types those same 24 words in (Settings → 🔐 Security → **Restore from recovery words**), picks his *own* passphrase, and suddenly his Molly can read all the same encrypted stuff yours can. That's how you two share passwords without ever sending a password.

The grid input is friendly: type a word, hit space, jumps to the next cell. Paste a numbered list ("1. apple 2. bridge…") and it strips the numbers automatically. The 📋 Paste button fills all 24 in one click.

> ⚠️ If you lose your passphrase **AND** your 24 words, the safe deposit box is gone forever. Anything Molly was protecting can't be read. So: write the words down somewhere real.

---

## 🔑 Then: Molly remembers every site password (Settings → Sites + Molly Helper)

This is the one that should save you the most time daily.

### In Settings → Sites

Every site card now has a **Credentials** section. Each site can hold **multiple logins** — really useful for, e.g.:

- One **C4S** site, but two different stores (your **CoC store** + your **PoA store**) — give them separate labels and Molly tracks them as siblings.
- An **OnlyFans** main + a backup account — same site, two credentials, one marked as primary.

For each credential row you get: a **label** ("default", "CoC store", whatever you call it), a **username** field, and a **password** field. The password field only wakes up when your keystore is unlocked — otherwise it shows 🔒 with a gentle "unlock first" hint.

### In Molly Helper (your daily driver)

Every site card now shows the per-credential row(s) with two new buttons:

- **👁 Reveal** — shows the password in the card for **10 seconds**, then auto-hides.
- **📋 Copy password** — puts it on your clipboard. Molly will **clear your clipboard 30 seconds later** so the password isn't sitting there for whatever app you copy something into next.

If a site has more than one credential, the card expands to label each row (your CoC store and your PoA store sit next to each other so you grab the right one).

If the keystore is locked, the cards show 🔒 instead and a friendly banner appears at the top — **Unlock now**, type your passphrase, banner goes away, all the Reveal/Copy buttons wake up. You never have to leave Molly Helper to unlock.

---

## 🌀 Finally: Molly runs your ATW repost bot for you

You know the **ATW repost bot** Robert built you (the thing that re-posts your AllThingsWorn listings on a schedule)? That whole script now lives **inside Molly**.

### Settings → 🌀 ATW Repost

One tab to set it all up:

- **🩺 Health check** — Molly looks for everything the bot needs: Node.js, Chrome, the bot's own files, the `node_modules` install. Each row is ✓ green or ✗ red with a button to fix it ("Get Node", "Get Chrome", "Install bot dependencies").
- **🔒 Unlock banner at the top** — if your keystore is locked, you unlock it *right here* without navigating away. (Earlier versions made you go to Security and back — fixed.)
- **🔑 Credentials** — your ATW email + password. The password gets encrypted by your keystore the moment you save it.
- **⏱ Schedule + behavior**:
  - **Cadence** — how often to run: 1h / 2h / **4h default** / 6h / 12h / 24h.
  - **Repost spread** — how many days to spread the repost slots across (default 7).
  - **Waking-hour window** — start hour + end hour, so reposts only schedule for hours you'd actually be awake.
  - **Delay between submissions** — 1–60 seconds, to stay polite.
  - **Headless toggle** — run silently in the background, or show the Chrome window so you can watch.
- **▶️ Run now** — fires the bot on demand, without waiting for the schedule.
- **⬇ Install bot dependencies** — one-click `npm install`. Shows a progress log. ~30 seconds on a decent connection.

### Sidebar → 🌀 Jobs

A new sidebar entry shows every background job Molly is running + the **last 50 runs per job**. Each run row has a colored status pill (running / ✓ success / ✗ failed), the start time, a one-line summary ("Submitted 47 of 47 listings"), and an expandable log if you want the details. Each job has **▶️ Run now** and **⏸ Disable** buttons.

The bot will fire automatically on its cadence as long as Molly is open. (Molly still needs to be open for now — a system-tray background mode is a future thing.)

### One-time setup

The very first time you open the ATW tab, the bot files don't have `node_modules` yet — that's why the **Install bot dependencies** button is there. You only run it once (and again whenever Molly ships a bot update — Molly will tell you).

You **do** need **Node.js 18+** and **Google Chrome** installed on the Mac. Both are free, both have one-click installers, and Molly's health check links you straight to nodejs.org / chrome.com. Robert can install both if you need a hand.

---

## 🌷 Everything else stays the same

All your existing data, settings, journal entries, schedules, bundles, backups — untouched. Auto-backup on launch is still humming. (And now your backups also include the encrypted keystore, so if you ever restore from a backup ZIP, your passwords come along for the ride — *as long as you remember the passphrase that locked them*.)

---

A note on **what to do this week**:

1. Go to **Settings → 🔐 Security** and set a passphrase.
2. **Reveal your 24 recovery words** and write them on paper. Tell Robert (or DM him the words so his Molly can read your passwords too).
3. Go to **Settings → Sites** and start putting passwords in for the sites you use daily — even just 3-4 to start. Then watch how nice **Molly Helper** feels with the **📋 Copy password** button right there.
4. Whenever you're ready, do the **🌀 ATW Repost** setup. Click the **Install bot dependencies** button. Type your ATW email + password. Click **▶️ Run now**. See it work.

You're doing the work. Molly is just trying to carry a few more boxes for you now. ✨💕

— Molly, your soft little helper

*(v1.13.0, posted 2026-05-22)*
