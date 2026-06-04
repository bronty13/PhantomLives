# Molly release messaging — a love note from Molly to Sallie

**Every time we cut a Molly release, replace the auto-generated GitHub
release body with a hand-crafted message from Molly to Sallie.** The
auto-message ("Auto-built from tag molly-vX.Y.Z…") is fine for
machines but ugly for the human reading it. Sallie *is* the user;
treat the release notes as a personal note from her app.

## Docs are part of the release — no exceptions

**Before every Molly release commit, update USER_MANUAL.md (and any
other Sallie-facing docs — `WHATS_NEW_*.md`, in-app help text) in the
same 200%-cute voice as the rest of the manual.** A "technically
accurate but textbook" doc update doesn't count. If the manual still
describes the old behaviour for a feature/screen/flow that changed,
that is a **release blocker** — bump a `.1` and re-cut rather than
shipping a manual that's out of step with the app.

Voice split:

- **200% cute** (Sallie-facing): `USER_MANUAL.md`, `WHATS_NEW_*.md`,
  in-app help / tooltip text, GitHub release body.
- **Normal dev voice** (engineer-facing, but still kept current):
  `README.md`, `CHANGELOG.md`, `HANDOFF.md`, code comments,
  `DESIGN.md`, `ROADMAP.md`.

Both must be current at release time — only the *voice* differs.

## Tone

- **200% cute.** This is non-negotiable. Sparkles ✨ hearts 💖 stars 🌟,
  warm encouraging voice, sweet pet-name energy. Molly is talking to her
  best friend.
- First-person from **Molly**, second-person to **Sallie**. (`"I added"`,
  `"You can now"` — never `"the app"` or `"users"`.)
- Frame everything around what *Sallie does and feels*, never engineering
  internals. "I cleaned up the Custom Bundle form so when you pick URL
  link you don't have to fill in fluff Robert is going to override
  anyway" — not "validate_custom_delivery now keys off delivery_kind."
- Encouragement, not interrogation. If something needs verification,
  invite her: *"will you peek at X for me?"* — not *"please test X"*.

## Structure

Use this skeleton; tweak when the release calls for it but keep the
sections recognisable:

```markdown
💖 **Hey Sallie!** 💖

Itty-bitty note from your girl Molly — I got some makeover sparkles!
(v{VERSION}, fresh out of the oven 🧁)

## ✨ What's new since {PREV_VERSION}

- 🪙 **Headline feature** — one or two sentences, in Sallie-language.
- 🎁 **Smaller bug fix** — what was annoying, what's better now.
- *(group related fixes; one bullet per shipped change is fine)*

## 🪟 Updating on your Windows machine

Open Molly → **Settings → Updates → Check for updates** and let me
swoop in! Or grab the installer fresh from this page if the in-app
updater is being shy.

## 🧪 Will you peek at these for me?

1. **First thing Sallie should try** — concrete click path
   (Sidebar → 🪙 Social → tap +1 on TikTok — should ✨ching✨ and the
   bar goes green at 2/2).
2. **Edge case worth a glance** — what to watch for.
3. **Regression check** — a previously-working flow that touched
   the same code, just to be safe.

## 💌 If something feels wonky

Yell at me through Claude Code — I'll get it sorted same day. 🩷

xoxo,
Molly 🪙✨
```

## Required content

- **Diff window**: include every commit between `molly-v<PREV>` and
  `molly-v<NEW>` (use `git log molly-v<PREV>..molly-v<NEW> --oneline
  -- Molly/`) — not just the headline version. Sallie hops several
  patch versions sometimes; don't drop the in-between fixes.
- **Windows-only test steps.** Sallie runs Windows exclusively. No
  macOS-specific instructions, paths, or screenshots. "Right-click the
  app" on macOS = "Properties → Unblock" on Windows; pick the Windows
  one. If a feature was only manually verified on macOS by you, say so
  honestly: *"I built this on a Mac so will you give it an extra
  squeeze on Windows for me?"*
- **Concrete click path** for the headline feature — exact sidebar
  → tab → button sequence Sallie needs to follow to see the change.
- **One regression check** when the change touches an existing flow —
  pairs nicely with each headline item.

## Workflow

After `gh run watch` reports the publish-feed job has flipped the
draft to published, immediately:

1. Compose the message in a heredoc.
2. `gh release edit molly-v<VERSION> --notes "$(cat <<'EOF' ... EOF)"`
   to replace the auto-generated body.
3. Confirm with `gh release view molly-v<VERSION>` that the new body
   landed.

Don't wait for the user to ask. Cute message → release body update →
*then* announce to the user that the release is live.
