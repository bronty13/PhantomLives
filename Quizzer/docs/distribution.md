# Distributing Quizzer & shipping updates

There are **two** very different things to distribute, and only one is hosted:

| What | How it's distributed | Hosted? |
|---|---|---|
| **The creator** (the authoring SPA) | One permanent web address you bookmark | **Yes — this doc** |
| **A deployed quiz / wheel** | A self-contained file the creator downloads for you to email/host/hand out | No — per-activity output |

This document is about hosting the **creator** so you keep a single bookmark and
get updates just by refreshing — and so the quizzes, wheels, and branding you've
authored **are never lost** across updates.

## Why hosted, not "open a new file each time"

The creator stores everything you make in the browser's **IndexedDB**, which is
keyed to the page's **origin**. A `file://` page's origin is path-dependent — open
a freshly-downloaded copy from a new folder and the browser may treat it as a
different origin and orphan everything you authored. A fixed `https://…` address
has one origin forever, so updates never touch your data.

(Deployed quizzes/wheels are the opposite case on purpose: they're meant to run
from anywhere, including `file://` and offline, so they read their data from an
inlined `window.__QUIZ__` and never depend on origin.)

## One-time setup (GitHub Pages)

1. Create a **public** repo to host the page:
   ```bash
   gh repo create bronty13/quizzer --public --description "Quizzer (hosted creator)"
   ```
2. Do the first deploy (creates `index.html` + `version.json` on the repo):
   ```bash
   npm run deploy
   ```
3. Enable Pages: the repo's **Settings → Pages → Deploy from branch → `main` /
   `root`**. After ~1 minute the creator is live at:
   ```
   https://bronty13.github.io/quizzer/
   ```
4. **Open that link and bookmark it.** That bookmark is permanent; everything you
   author from it persists across updates.

Override the repo with `PAGES_REPO=owner/name npm run deploy`.

## Shipping an update (every release)

1. Make the change; bump **both** `version` in `package.json` **and**
   `APP_VERSION` in `src/shared/appMeta.ts` (keep them equal — the deploy script
   refuses to publish if they drift, because the update banner compares them).
2. Add a short, friendly entry to the **top** of `WHATS_NEW` in
   `src/creator/data/whatsNew.ts` (its `version` = the new version). This is the
   in-app **What's New** popup shown once after updating — separate from the
   technical `CHANGELOG.md`.
3. Update `USER_MANUAL.md` / `README.md` if behavior changed, and add a
   `CHANGELOG.md` entry.
4. Run checks: `npm run typecheck && npm test`.
5. Deploy:
   ```bash
   npm run deploy
   ```
   This asserts the versions match, builds the full pipeline, **restores the
   committed template stubs** the build regenerated (so the outer repo's working
   tree stays clean — see the README's "two-bundle architecture"), writes
   `version.json`, and pushes to the Pages repo.

What the author experiences next time they open the bookmark:

- A green **"A newer version of Quizzer is ready — Update now"** bar appears at
  the top. One click reloads to the latest.
- After updating, a **"What's New 🎉"** popup shows that version's highlights,
  then never nags again for that version (the last-seen version is stored in
  `localStorage` as `quizzer.lastSeenVersion`).

## How the in-app update pieces work

- `src/shared/version.ts` — numeric version comparison (so `0.4.10 > 0.4.9`).
- `src/shared/appMeta.ts` — `APP_VERSION`, the running build's version.
- `src/creator/data/whatsNew.ts` — the friendly release notes + `unseenNotes()`.
- `src/creator/components/UpdateBanner.tsx` — on load, best-effort fetches
  `version.json` next to the app; if it advertises a newer version than the
  running build, shows the banner. Silent when offline or opened from a file.
- `src/creator/components/WhatsNew.tsx` — the popup shown once per new version.

## Sending release notes by message (optional)

Alongside the in-app popup you can cut a GitHub release for your own record:

```bash
gh release create quizzer-v$(node -p "require('./package.json').version") \
  --title "Quizzer v$(node -p "require('./package.json').version")" \
  --notes "…highlights…"
```

## Fallback: send the creator as a file (no hosting)

If you ever can't host: `npm run build`, then send `dist/index.html` — it's a
single self-contained file you double-click. Downside: it re-downloads every
update, and **authored quizzes can be orphaned** if the file lands at a new path
(the IndexedDB origin changes). Prefer the hosted route above for the creator.

## Future option: offline support (PWA)

The hosted creator needs internet to load each time. If you often author
offline, we can add a service worker (cache the app + "update ready" prompt).
Not done yet to keep the build a single file; ask if you want it.
