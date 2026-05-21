# Molly 💕

> A cute, pretty, girly desktop app for a content creator who works across multiple personas — clips, customers, schedules, money, promos, all in one warm little place. Runs on macOS and Windows.

This is a single-user gift app, built for Sallie. The 1.0.0 milestone is feature-complete; everything below is shipped.

## What's in the app

| Tab | What it does |
|---|---|
| 🏠 **Home** | A rotating cute saying + a dashboard: clips MTD, per-persona breakdown, reuse detection, recent imports, today's reminders. |
| 📔 **Molly's Log** | Captain's-log-style personal journal. Append timestamped entries with optional file attachments; edit/delete any past entry; grep-toggle filter. |
| 🔔 **Reminders** | Overdue / Today / Coming-up-7d with a satisfying check-off + 10-second undo. Schedules tab for the rules (no-cron wizard, six cadence kinds). Five reminders preloaded. |
| 📅 **Calendar** | Month grid with persona-colored clip pills imported from MasterClipper. Click a pill for the clip detail + your own Tiptap notes. |
| 🎬 **Clips** | Searchable, sortable clip list. **📂 Import CSV** sucks in a MasterClipper export with persona-code mapping; idempotent on re-import. |
| 👯‍♀️ **Customers** | Auto-UID (`YYYY-MM-DD-#####`), persona binding, 5 email slots (primary picker), full mailing address (ISO country), 2 phones with mobile + primary flags, ⭐ VIP toggle, product/interest/kink chips, rich-text notes. |
| 💅 **Molly Helper** | Per-persona grid of color-tinted site cards. **Open** launches the site, **Copy user** drops the username on your clipboard. |
| 📣 **Promos** | Reddit / X / Instagram / TikTok promo tracker. Optional clip-link. Reports the per-platform count. |
| 💖 **Income** | Adhoc one-offs, monthly site-income wizard grouped by persona, generic sales-report CSV importer with auto-detected date+amount columns. |
| 🧾 **Expenses** | One-off + recurring (cadence-driven). Attachments (receipts), full or partial exclusion (`$30 of this $100 was personal`). |
| 📊 **Reports** | MTD vs Prior MTD vs YTD income–expense–profit, per-persona site bars, Promos breakdown, **📄 Export CSV**. |
| ⚙️ **Settings** | Personas, Sites, Platforms, Products, Interests, Kinks (~350 preloaded), Data export, Updates, Backup. |

The persona switcher at the top right (CoC / PoA / Sa / ★ All) is a global filter — the whole UI recolors per persona via CSS custom properties.

## Quick start

### Sallie (Windows)

See [INSTALL.md](INSTALL.md). Short version: download `Molly_1.0.0_x64-setup.exe` from the [Releases page](https://github.com/bronty13/PhantomLives/releases), double-click, click through. Done.

### Robert (Mac dev)

```sh
brew install rust pnpm librsvg imagemagick     # one-time
cd Molly
pnpm install
pnpm tauri dev                                 # hot-reload dev
./build-app.sh                                  # build + install to /Applications/
./run-tests.sh                                  # cargo test --lib  (12 tests)
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
│   ├── src/                backup.rs, attachments.rs, export.rs, fsutil.rs, lib.rs
│   ├── migrations/         9 SQL migrations
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
| 1.0 | **🎁 Gift release: cute sayings banner + cascade docs.** *(this build)* |
| ⏸ 8 | Per-site sales-report parsers (deferred — see [PHASE_8_PARSERS.md](PHASE_8_PARSERS.md)). |

## Built with love
For Sallie, the brave, the bold, and the beautifully consistent. 💕
