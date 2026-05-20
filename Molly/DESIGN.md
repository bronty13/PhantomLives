# Molly — Design Notes

> Why Molly looks the way it does. Snapshot of UX / theming decisions taken across 7 phases.

## The brief

Sallie is a content creator working across three personas (Curse of Curves, Princess of Addiction, Sheer Attraction). She wanted **one** place to keep her work — sites, customers, schedule, money, promos — and she wanted it to feel **cute, pretty, girly, and fun**. Not a utility. Not a spreadsheet. Something that makes opening it the small bright moment of a long admin afternoon.

Three design constraints fall out of that:

1. **Persona-first**, not view-first. Every screen filters by the chip you tapped at the top.
2. **Soft pastel + display fonts**, not flat-design grays. The whole palette is rooted in the active persona's colors.
3. **Mass over polish on day one** — better to ship 7 phases that all work than a single tab that's been A/B'd to death.

## Visual system

### Color: persona-driven CSS variables

Every persona owns five colors:

| Token | Used for |
|---|---|
| `--persona-primary` | Active chips, pill backgrounds, accent bars |
| `--persona-secondary` | Sidebar background, gradient stops |
| `--persona-tint` | Page background, soft card fills |
| `--persona-accent` | Headings, buttons, important text |
| `--persona-text` | Body text on light backgrounds |

Switching persona swaps these on `:root` via `state/theme.ts::useApplyPersonaTheme`. Components consume them through Tailwind's `rgb(var(--persona-X) / <alpha>)` syntax. Result: a single click recolors **every** background, border, button, pill, chart bar, and badge — without any component knowing about the active persona directly.

Personas ship preloaded but are fully editable in **Settings → Personas**. A user could rename "Curse of Curves" to "Goblin Mode" and recolor everything to forest green if she wanted.

### Typography: cute by default, not utility

| Family | Where |
|---|---|
| **Comfortaa** | Display: headings, persona names, big counts |
| **Nunito** | Body: forms, table rows, anything <16pt |
| **Pacifico / Caveat / Dancing Script / Sacramento / Indie Flower / Shadows Into Light / Patrick Hand / Kalam / Chewy** | Sayings banner (10-way random rotation) |

The 10 sayings fonts deliberately span a range — some scripty (Pacifico, Sacramento), some handwritten (Caveat, Patrick Hand), some chunky (Chewy). On every component mount we pick a random font *and* a random saying so the same screen never quite reads the same twice.

### Spacing + shape

- **2xl / 3xl border radii** everywhere. Nothing in Molly has a sharp corner that isn't a literal table cell. Persona-tinted soft shadows on cards.
- **Page max-width 4–6xl**, centered. A wide desktop monitor doesn't smear data across 1920 pixels; the content sits in a comfortable column.
- **Sidebar at fixed 240 px** (HStack pattern, not `NavigationSplitView` — see CLAUDE.md). Toggleable with ⌘+S / Ctrl+S.

## Information architecture

The sidebar maps directly to the mental model:

```
🏠 Home          ← "what should I think about right now"
🔔 Reminders     ← "what needs doing today" (red badge = overdue + today)
📅 Calendar      ← "when am I dropping things"
🎬 Clips         ← "what did I make"
👯‍♀️ Customers     ← "who buys from me"
💅 Molly Helper  ← "where do I go to do the work" (site launcher)
📣 Promos        ← "where did I tease it"
💖 Income        ← "what did I earn"
🧾 Expenses      ← "what did I spend"
📊 Reports       ← "show me the year"
⚙️ Settings      ← "make Molly mine"
```

Each entry sits where it sits because of how often it gets used in a real day: reminders + calendar are always near the top because they have time-pressure; settings is at the bottom because you only touch it once.

## UX choices worth calling out

- **Two-tap delete (`ConfirmButton`)**. No modal dialogs; the button itself changes to "Confirm?" for 3 seconds. Faster + less interrupting.
- **Check-off confetti (`CheckOffBurst`)**. Persona-tinted CSS particles + a 💕. Reminders pay you back for doing them.
- **`✨ another` shuffle** on the sayings banner. Tiny dopamine loop. Cheap to add, often used.
- **Persona-colored chip everywhere a row has a persona binding**. A glance at a customer list tells you which persona owns each row.
- **Site-tinted top-borders on Molly Helper cards.** Each site is a soft brand mark of itself.

## What I deliberately did **not** do

- **No animations longer than 240 ms.** The confetti is half a second, the check-off circle is 120 ms. Long animations turn cute into slow.
- **No dark mode.** Sallie's palette is built around pastel + warm — a dark mode would either re-invent every color (huge surface) or feel like a different app.
- **No keyboard shortcuts beyond ⌘+S / Ctrl+S** (sidebar toggle). She's mousing; shortcuts add nothing.
- **No drag-to-reorder** in the lists. The sort buttons cover the actual need.
- **No graph library.** Bar charts are `<div style={{ width: 'X%' }}>` and look better.
- **No icon library.** Emojis are warmer + cross-platform free + need no licensing.

## Hidden-feature inventory

These are tucked away but worth knowing about:

- **Cmd/Ctrl + S** toggles the sidebar.
- **Click the saying** in the sidebar to re-roll it.
- **Settings → Data** has a `📦 Export everything` button that writes a single zip you can drop to me in Slack.
- **Settings → Backup → Test** verifies a recent backup (does it contain `molly.db`?) without restoring.
- **Settings → Backup → Restore** ALWAYS writes a `Molly-pre-restore-…zip` first. Even click-by-accident restores are reversible.
- **VITE_MOLLY_DEV=1** during dev unlocks the **Import full export** button on Settings → Data (lets Robert load Sallie's zip).
- **Dropping a clip from MasterClipper twice** re-runs UPSERT on the clip UID; doesn't duplicate. Your own `mollyNotes` survive the re-import.

## What's intentionally aging

A few choices that work today but might want a refresh later:

- **All persona theming lives in the DB rather than as named themes.** That's why you can recolor freely. Trade-off: there's no "reset to default" button per persona.
- **No Tiptap dependency tree-shake.** The notes editor pulls in ~200KB. Acceptable for desktop; would matter on web.
- **JS bundle is `~750KB` minified.** Mostly Tiptap. Single-bundle is fine for a Tauri app on Apple Silicon and modern Windows; if we ever target a low-end machine, code-split.

## Why it's called Molly

Because every part of the app pretends to be a small soft helper named Molly speaking to Sallie ("Hi, I'm Molly 💕", "go make something pretty", `✨ another`). Naming the app after the helper rather than the function — `Income Tracker Pro` etc. — was the single biggest tone decision. The Comfortaa + heart in the icon make the brand. Don't break that.
