# CalendarMaker release emails (to Jan)

**Every time we ship a CalendarMaker release, send Jan a short, friendly email**
telling her what's new, what to try, and reassuring her nothing breaks. This is a
release blocker, the same way the in-app **What's New** note and `USER_MANUAL.md`
must be kept current.

This is a quieter cousin of the Molly release-messaging rule — warm and personal,
but **plain and practical, not cutesy**. Jan is not tech-savvy, has low vision,
and uses a **Windows 11 laptop with an external mouse**.

## Voice & format rules

- **Warm and personal**, signed off affectionately — but calm and clear, not
  bubbly. No emoji storms (one is fine), no jargon.
- **Say "click"** (she uses a mouse), never "tap". Reference Windows, not Mac.
- **Short lines and short paragraphs.** Easy to read at a glance / at large zoom.
- **Numbered steps** for anything she does. One action per step.
- **Always reassure**: her saved calendars are never lost; she can't break
  anything.
- **Lead with the benefit**, not the version number. Put any version number at the
  very bottom if at all.
- Mention she can make text bigger: **A+** in the Help window, or hold **Ctrl**
  and press **+** for the whole screen.

## Recurring update email — skeleton

```
Subject: A little update to your CalendarMaker

Hi Jan,

I added <one-sentence benefit> to your calendar app.

To get it: just open CalendarMaker from your bookmark. If you see a green bar
at the top that says "A newer version is ready," click "Update now." Your
calendars stay exactly as they were.

Would you try this for me?
1. <one concrete thing to try, one action>
2. <a second simple thing, if any>
Then let me know it worked (or send me a screenshot if anything looks off).

Anything confusing? Click the "Help" button at the top — and you can make the
words bigger with the A+ button.

Love,
<you>
```

### Writing the "what to try" steps

Each release, look at the user-facing changes (the new top entry in
`src/data/whatsNew.ts`) and turn each into **one plain instruction Jan can do with
the mouse** and verify by eye. Skip anything internal. Examples:

- New verse picker → "Click a day, choose Bible Verse, and type John 3:16."
- New theme → "Open a calendar, click Themes, and try the new one."
- Printing change → "Click Export PDF and open the file to check it looks right."

Keep it to **1–3 steps**. If a release has nothing for her to test, say so plainly
("nothing you need to do — it just works a little better").

## First-time / onboarding email

Use this when moving Jan from the old copied-file version to the hosted bookmark.
The current version is saved below as `onboarding-current.md` — copy it, adjust if
needed, and send.

### Migrating her existing calendars (important)

The hosted app is a **different web address** from the old file, so calendars she
saved in the old version **won't appear automatically** in the new one. Don't make
Jan do an export/import alone. Instead, **offer to move them for her** on a
screen-share.

→ Step-by-step screen-share checklist: **`docs/migration-checklist.md`** (open both
versions, Export bundle from each old calendar → Import into the new app → verify →
swap the bookmark). Nothing can lose data — it only copies.

## After sending

- Keep a copy of what you sent (paste it under a dated heading in your notes, or
  reply-all to yourself), so the wording stays consistent release to release.
- Optionally cut a GitHub release for your own record (see `docs/distribution.md`).
