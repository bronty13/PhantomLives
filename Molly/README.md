# Molly 💕

> A cute, pretty, girly desktop app for a content creator who works across multiple personas — clips, customers, schedules, money, promos, all in one warm little place. Runs on macOS and Windows.

This is a single-user gift app, built for Sallie. 1.0.0 was the original gift release; the app has grown substantially since — including (as of v1.17.1) bundle previews with sample frames, holidays on the calendar, a global content-tag taxonomy with per-day FanSite tagging, a dedicated 🔴 Reddit ops hub (daily to-do · subreddit tracker · post log · captions · hours + reward milestones), and a dark-mode toggle. See [CHANGELOG.md](CHANGELOG.md) for the full sweep.

## What's in the app

| Tab | What it does |
|---|---|
| 🏠 **Home** | A rotating cute saying + a dashboard: clips MTD, per-persona breakdown, reuse detection, recent imports, today's reminders. |
| 📔 **Molly's Log** | Personal journal — timestamped notes to self with optional file attachments. Edit/delete any past entry. Past entries render in a handwritten font (Caveat). `grep` checkbox toggles regex search. |
| 🔔 **Reminders** | Overdue / Today / Coming-up-7d with a satisfying check-off + 10-second undo. Schedules tab for the rules (no-cron wizard, six cadence kinds). Three reminders preloaded. |
| 📅 **Calendar** | Month grid with persona-colored clip pills imported from MasterClipper + 🎉 themed holiday pills (18 US defaults). Three opt-in overlays (per-persona, persisted): 🏷️ FanSite day tags · 🎬 Clip tags · 🔴 Reddit posts. Click a clip pill for the detail + your own Tiptap notes + a content-tag picker. |
| 🎬 **Clips** | Searchable, sortable clip list. **📂 Import CSV** sucks in a MasterClipper export with persona-code mapping; idempotent on re-import. |
| 🛍️ **C4S Store** | Read-only Clips4Sale catalog snapshot for both stores (CoC + PoA). ✨ Import C4S CSV auto-detects which store from the `Performers` field, then atomically replaces the snapshot with row-count verification. Dashboard with status breakdown, top categories, top keywords, pricing stats + a tiered cute "X days old" stale-data banner. Sortable, regex-searchable grid; full-page detail view; per-column visibility toggles in Settings. |
| 🎁 **Bundles** | Compose delivery packages for Robert. Four flavors all live: **Content** (title + persona + text-or-audio description + 3+ drag-reorder categories + drag-reorder media + go-live date + bundle-level content tags), **▶️ YouTube** (title + persona + text-or-audio description + 1+ video clips, video-only + go-live date + special instructions — Content minus categories), **Custom** (delivery platform = site picker OR URL + recipient + price-or-handled-in-platform + bundle-level content tags), **Fan Site** (whole month of posts on a calendar — click each day → short message + files + per-day content tags). Publishes as a deterministic, SHA-256-hashed two-layer ZIP to `~/Downloads/Molly bundles/` ready to drop into Slack. Pre-publish wizard with **inline image/video previews + 5 sample frames per video** + click-to-jump validation checklist. Content + YouTube publishes also auto-upsert a Clips row with status `Bundled` and mirror the bundle-level tags onto it. Content tags flow through to `info.md` + `Molly.log` inside the published ZIP. |
| 🔴 **Reddit** | Daily ops hub with five sub-sections: ✅ Today (daily to-do, 11 quick-add chips, 5 color categories, auto-reset at midnight) · 📌 Subreddits (33 CoC subs seeded; star/category/verified/rotation/last-posted/notes; filter+sort; mark-posted writes to post log; configurable rotation reset — Auto derives Ready/Tomorrow/Resting from last-posted + an editable rest window, or Manual with a per-sub ↺ reset) · 📅 Post log (bucketed Future/Tomorrow/Today/Yesterday/Earlier; future-scheduled posts allowed; auto-completes from tracker) · 💬 Captions (copy-to-clipboard library with optional content-tag categories) · ⏱ Hours (clock-in/out, live HH:MM:SS, today/week/month totals, session log, 🎁 reward-milestone progress bars). |
| 👯‍♀️ **Customers** | Auto-UID (`YYYY-MM-DD-#####`), persona binding, 5 email slots (primary picker), full mailing address (ISO country), 2 phones with mobile + primary flags, ⭐ VIP toggle, product/interest/kink chips, rich-text notes. |
| 💅 **Molly Helper** | Per-persona grid of color-tinted site cards. **Open** launches the site, **Copy user** drops the username on your clipboard. |
| 📣 **Promos** | Reddit / X / Instagram / TikTok promo tracker. Optional clip-link. Reports the per-platform count. |
| 💖 **Income** | Adhoc one-offs, monthly site-income wizard grouped by persona, generic sales-report CSV importer with auto-detected date+amount columns. |
| 🧾 **Expenses** | One-off + recurring (cadence-driven). Attachments (receipts), full or partial exclusion (`$30 of this $100 was personal`). |
| 📊 **Reports** | MTD vs Prior MTD vs YTD income–expense–profit, per-persona site bars, Promos breakdown, **📄 Export CSV**. |
| ⚙️ **Settings** | Personas · 🎨 Appearance (light/dark/system) · Sites · Platforms · Products · Interests · Kinks (~350 preloaded) · C4S · 🎁 Bundler · 🏷️ Content tags · 📝 Notes · 🎉 Holidays (18 US defaults) · 🎁 Rewards (hour-goal milestones) · 🔐 Security · 🌀 ATW Repost · Data export · Updates · Backup. |
| 💌 **Manual** | In-app user guide — `USER_MANUAL.md` rendered with a hand-rolled markdown parser, persona-tinted headings, right-rail table-of-contents that highlights as you scroll. |

The persona switcher at the top right (CoC / PoA / Sa / ★ All) is a global filter — the whole UI recolors per persona via CSS custom properties.

## Quick start

### Sallie (Windows)

See [INSTALL.md](INSTALL.md). Short version: download the latest `Molly_X.Y.Z_x64-setup.exe` from the [Releases page](https://github.com/bronty13/PhantomLives/releases), double-click, click through. Done.

### Robert (Mac dev)

```sh
brew install rust pnpm librsvg imagemagick     # one-time
cd Molly
pnpm install
pnpm tauri dev                                 # hot-reload dev
./build-app.sh                                  # build + install to /Applications/
./run-tests.sh                                  # cargo (258) + vitest (197) = 455 tests as of 1.23.0
```

To cut a signed release: `git tag -a molly-vX.Y.Z -m "…" && git push origin molly-vX.Y.Z`. CI builds + signs both platforms, drops a draft GitHub release with `latest.json` for the auto-updater.

## Default file locations

| What | Mac | Windows |
|---|---|---|
| App data (DB + attachments) | `~/Library/Application Support/com.phantomlives.molly/` | `%APPDATA%\com.phantomlives.molly\` |
| Auto-backups | `~/Downloads/Molly backup/` | `%USERPROFILE%\Downloads\Molly backup\` |
| User exports | `~/Downloads/Molly export/` | `%USERPROFILE%\Downloads\Molly export\` |

## Personas (preloaded; editable in Settings → Personas)

| Code | Name | Primary |
|---|---|---|
| `CoC` | Curse Of Curves | Baby pink `#FFC0CB` |
| `PoA` | Princess of Addiction | Red `#C8102E` |
| `Sa` | Sheer Attraction | Tan `#D2B48C` |

## Auto-backup safety net

Every launch zips `app_data/` into `Downloads/Molly backup/Molly-YYYY-MM-DD-HHmmss.zip`. 14-day retention default, 5-minute debounce. Test / Restore / Reveal from Settings → Backup. Restore always writes a `Molly-pre-restore-…zip` safety archive first.

## Auto-update

`tauri-plugin-updater` checks `https://github.com/bronty13/PhantomLives/releases/latest/download/latest.json` on launch + on demand from Settings → Updates. Signed with our minisign key (`tauri.conf.json::plugins.updater.pubkey`).

## Repo layout

```
Molly/
├── src/                    React + TS frontend
│   ├── components/         Reusable UI bits (incl. SayingsBanner, ColorPicker, ConfirmButton)
│   ├── views/              One folder per feature area
│   ├── data/               Typed SQL wrappers
│   ├── lib/                Pure helpers: cadence, csv, money, useAsyncRefresh, uid, salesReport
│   └── state/              React hooks (personas, theme)
├── src-tauri/              Rust backend
│   ├── src/                backup.rs, attachments.rs, c4s.rs, export.rs, fsutil.rs, history.rs, log.rs, lib.rs
│   ├── migrations/         36 SQL migrations (001 init → 036 youtube_bundle)
│   └── icons/              Generated icon set
├── install.sh              Mac: copy .app to /Applications + relaunch
├── build-app.sh            Mac: build + install + relaunch
├── run-tests.sh            cargo test wrapper
├── .github/workflows/release-molly.yml   Tagged → signed .dmg + .exe + latest.json
├── README.md
├── USER_MANUAL.md          Sallie-facing tour
├── INSTALL.md              Sallie-facing install + export walkthrough + dev counterpart
├── HANDOFF.md              Architecture map for future devs
├── DESIGN.md               Why Molly looks the way it does
├── PHASE_8_PARSERS.md      Deferred per-site sales-report parser plan
├── OUT_OF_SCOPE.md         What we deliberately won't build
└── CHANGELOG.md
```

## Phases

| Phase | Scope |
|-------|-------|
| 0 | App shell, icon, persona theming, backup-on-launch, CI release pipeline. |
| 1 | Settings (personas/sites/products/interests) + Customer tracker + Molly Helper. |
| 2 | Calendar + MasterClipper import + dashboard widgets. |
| 3 | Scheduling engine + reminders + check-off. |
| 4 | Income (adhoc + per-site) + expenses (one-off + recurring) + reports. |
| 5 | Full export → dev / import on dev / auto-update polish. |
| 6 | Generic sales-report CSV importer. |
| 7 | Social promotion tracker (Reddit / X / Instagram / TikTok). |
| 1.0 | 🎁 Gift release: cute sayings banner + cascade docs. |
| 1.1 | Kinks taxonomy (349 preloaded + searchable picker w/ drag-to-reorder + inline create). |
| 1.2 | Products price + unit, customer fields (VIP, primary email, mailing address w/ ISO country, US states, two phones w/ format-as-you-type). |
| 1.3 | Per-customer history log (inline BLOB attachments via rusqlite). |
| 1.4 | Customer sales (full CRUD; lifetime pill; interleaved timeline; date picker). |
| 1.5 | Customer sales → Adhoc Income union + import-skip fix. |
| 1.6 | Calendar reminders + Clips grid sort/filter + reusable MoneyInput across 5 spots. |
| 1.7 | 📔 Molly's Log (Captain's-log-style personal journal w/ Caveat handwritten font). |
| 1.8 | 🛍️ C4S Store — Clips4Sale catalog import + browser (atomic overlay-replace, count-verify, tiered stale banner, per-column visibility, settings). |
| 1.9 | 🎁 Content Bundler (Phase 9, pt 1) — Content bundle type: persona-themed ZIP packages with validation engine, draft-then-publish wizard, prohibited-words guard, archive auto-purge. |
| 1.10 | 🎁 Content Bundler (Phase 9, pt 2) — Custom bundle (recipient + delivery platform + price) + Fan Site bundle (color-coded month-calendar with per-day messages & files). |
| 1.11 | 🔐 Keystore infrastructure (Phase 10) — passphrase-derived KEK wrapping a per-install DEK, AES-256-GCM at-rest crypto for secrets, rate-limited unlock, change-passphrase. |
| 1.12 | 🗝️ Site password manager (Phase 11) — site-credentials editor with primary + sub-credentials, last-rotated tracking, copy-to-clipboard, encrypted at rest via the Phase 10 keystore. |
| 1.13 | 🌀 Background jobs + ATW Repost (Phase 12) — every-4h scheduler running Sallie's `atw-repost-bot` with encrypted creds, full run-history + log viewer, manual-run + pause. |
| 1.14 | 📝 Notes (Phase 13) — Apple-Notes-style organiser: unlimited-depth folders, tags, WYSIWYG editor, attachments, regex find, MD/DOCX/PDF export, per-note fonts + paper colours + size. |
| 1.15 | 🎁🎉🏷️ Phase 14 — Bundle previews (inline image/video + 5 sample frames per video) · Holidays on the Calendar (18 US defaults, fixed + nth-weekday, two-color split-tone pills) · Content tags (global taxonomy on bundles, per-day FanSite tags, clip tags) · two Calendar overlay toggles (FanSite tags + Clip tags, per-persona). |
| 1.16 | 🎁 Content-tag propagation — bundle-publish mirrors bundle-level tags onto the clip row; content tags flow into `info.md` + `Molly.log` inside the published ZIP. |
| 1.17 | 🔴⏱🎨 Phase 15 — Reddit sidebar tab (Today / Subreddits / Post log / Captions / Hours) · 🎁 Reward milestones (global, multiple goals) · 🎨 Dark mode (light/dark/system) · 🌼 Licensed Paper Daisy font · removed unwanted "CoC/PoA content release" defaults · 3rd Calendar overlay for Reddit posts. **v1.17.1 hotfix** for migration-hash crash. |
| ⏸ 8 | Per-site sales-report parsers (deferred — see [PHASE_8_PARSERS.md](PHASE_8_PARSERS.md)). |

## Built with love
For Sallie, the brave, the bold, and the beautifully consistent. 💕
