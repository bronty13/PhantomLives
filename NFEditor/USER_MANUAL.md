# NFEditor — User Manual

NFEditor helps you build a NiteFlirt **Flirt Profile** or **Listing** without writing
HTML by hand, and makes sure what you paste into NiteFlirt won't get mangled.

## Opening it

Open the bookmarked link (or run `npm run dev` for a local copy). When a new version is
published, a green **Update now** bar appears at the top — tap it to refresh.

## Creating a document

From the home screen:

- **+ Flirt Profile** (7,000-character limit) or **+ Listing** (14,000-character limit).
- Or pick a **template** to start from a worked example.

Your documents save automatically to this browser and appear under **Your documents**.

## Editing

The toolbar gives you:

- **B / I / U / S** — bold, italic, underline, strikethrough.
- **Font / Size / color** — NiteFlirt supports seven font sizes (8–36pt); the Size menu
  shows each with its point size.
- **Paragraph / Heading 1–6** — with a heading color picker.
- **Align**, **bullet/numbered lists**, and a **divider**.
- **Insert ▾** — image, the payment buttons (Goody/PTV, Tribute, Flirt-call), wishlist
  link, section/box, video, and image map. Fill in the URLs and it drops the element in.

### Payment buttons

On NiteFlirt's *Payment Mail Buttons* screen, copy the button's **link** and **image
URL**, then Insert ▾ → the matching button type and paste them in. NFEditor outputs the
exact `<a href><img></a>` NiteFlirt expects.

### Images

Use any external image host (the `<img src>` only — don't include "link back" code).
Note: **animated GIFs uploaded to NiteFlirt's File Manager don't animate** — host
animated GIFs elsewhere.

## Output modes

Top-right toggle:

- **Compact** — modern inline styling; uses fewer characters.
- **Legacy table** — old-school `<table>`/`<font>`; renders most consistently on older
  mobile browsers. Uses more characters.

The **character counter** updates for the mode you've selected. Watch it: legacy mode
eats more of your budget.

## Safety checks (right-hand panel)

- **Character counter** turns amber near the limit and red over it.
- **Emoji** are blocked as you type and removed from anything you paste — NiteFlirt
  deletes an emoji **and everything after it** when you save, so this protects your page.
- **Strip warnings** tell you if pasted/imported content uses something NiteFlirt
  doesn't allow (like `class`).

## Preview

The **Preview** tab shows your page at three widths (375 / 800 / 1075px) the way
NiteFlirt's responsive layout will. Listings are capped at 820px wide.

## Getting it onto NiteFlirt

Open the **HTML output** tab:

- **Copy HTML** → paste into NiteFlirt's HTML box. (Primary way.)
- **Download .html** → saves a file (point your browser's downloads at
  `~/Downloads/NFEditor/`).

## Importing an existing listing

**Import HTML** (top bar) → paste your current Profile/Listing HTML → NFEditor turns it
into editable blocks and reports anything that would be stripped. Emoji are removed on
import.
