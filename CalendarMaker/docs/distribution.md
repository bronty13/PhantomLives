# Distributing CalendarMaker & shipping updates

CalendarMaker is a single self-contained `dist/index.html`. The easiest way to
give a non-technical, low-vision user painless updates is to **host it at one
permanent web address** and let them keep a single bookmark. Updating then means
they just open the bookmark — no downloads, no file copying, and **their saved
calendars are never lost** (a stable web origin keeps `localStorage` intact;
`file://` does not).

## Why hosted, not "send a new file"

`localStorage` (where calendars live) is keyed to the page's **origin**. A
`file://` page's origin is path-dependent — drop a new copy in a new spot and the
browser may treat it as a different origin and orphan every saved calendar. A
fixed `https://…` address has one origin forever, so updates never touch the data.

## One-time setup (GitHub Pages)

1. Create a **public** repo to host the page (the build embeds the NASB, so the
   page carries a `noindex` tag to stay out of search results):
   ```bash
   gh repo create bronty13/calendarmaker --public --description "CalendarMaker (hosted)"
   ```
2. Do the first deploy (creates `index.html` + `version.json` on the repo):
   ```bash
   npm run deploy
   ```
3. Enable Pages: the repo's **Settings → Pages → Deploy from branch → `main` /
   `root`**. After ~1 minute the app is live at:
   ```
   https://bronty13.github.io/calendarmaker/
   ```
4. **Send that link once.** The user opens it and **bookmarks it** (in the
   default browser). That bookmark is permanent.

Override the repo with `PAGES_REPO=owner/name npm run deploy`.

## Shipping an update (every release)

1. Make the change; bump `version` in `package.json` **and** `APP_VERSION` in
   `src/model/types.ts` (keep them equal).
2. Add a short, friendly entry to the top of `WHATS_NEW` in
   `src/data/whatsNew.ts` — plain language, large-print friendly. This is what the
   user sees in the **What's New** popup after updating (separate from the
   technical `CHANGELOG.md`).
3. Update `USER_MANUAL.md` if behavior changed — it **is** the in-app Help (Help
   button → User Manual), inlined into the build. Also update `CHANGELOG.md`.
4. Run checks: `npm run typecheck && npm test`.
5. Deploy:
   ```bash
   npm run deploy
   ```
   This builds, writes `version.json`, and pushes to the Pages repo.
6. **Email Jan** — what's new, what to try, reassurance. Use the template in
   `docs/release-email.md`. This is a release blocker, not an afterthought.

That's it. What the user experiences:

- Next time they open the bookmark (or if they leave it open, within a moment), a
  green **"A newer version is ready — Update now"** banner appears. One tap
  reloads to the latest.
- After updating, a large **"What's New 🎉"** popup shows that version's
  highlights, then never nags again for that version.

## How the in-app update pieces work

- `src/data/whatsNew.ts` — the friendly release notes + `unseenNotes()`.
- `src/app/components/WhatsNew.tsx` — the large-print popup (shown once per new
  version; the last-seen version is stored in `localStorage` as
  `cm.lastSeenVersion`). A brand-new install shows nothing (no update to announce).
- `src/app/components/UpdateBanner.tsx` — on load, best-effort fetches
  `version.json` next to the app; if it advertises a newer version than the
  running build, shows the banner. Silent when offline or opened from a file.
- `src/update/version.ts` — numeric version comparison (so `0.3.10 > 0.3.9`).

## Sending release notes by message (optional)

Alongside the in-app popup you can paste the same `WHATS_NEW` highlights into a
Proton Drive / email message, or cut a GitHub release for your own record:

```bash
gh release create calendarmaker-v$(node -p "require('./package.json').version") \
  --title "CalendarMaker v$(node -p "require('./package.json').version")" \
  --notes "…highlights…"
```

## Fallback: Proton Drive link (no hosting)

If you ever can't host: `npm run build`, upload `dist/index.html` to Proton Drive,
share the link. The user downloads and opens it. Downsides: they re-download every
update, and saved calendars can be lost if the file lands at a new path — prefer
the hosted route above.

## Future option: offline support (PWA)

The hosted page needs internet to load each time. If the user often works
offline, we can add a service worker (cache the app + "update ready" prompt). Not
done yet to keep the build a single file; ask if you want it.
