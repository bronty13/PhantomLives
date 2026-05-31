# PurpleDiary — Scoping Document

*A native macOS journaling app inspired by [Diarium](https://diariumapp.com),
built to PhantomLives conventions.*

> **Status:** Phase 1 implemented. The MVP journal (entries, mood, tags,
> people, timeline, calendar, search), launch-time backup, and the **privacy
> core** — SQLCipher encryption-at-rest, app-lock (Touch ID / passphrase), and a
> 24-word recovery key — are built and build-verified. Remaining Phase-1 polish
> and Phases 2–3 are below. Working name **PurpleDiary**.

---

## 1. One-line pitch

A local-first, private macOS diary where **your day arrives pre-assembled** —
photos, calendar events, places, and weather are pulled in automatically so
each entry starts with context instead of a blank page — layered with mood &
tracker self-logging, rich calendar/map/timeline browsing, and an app-lock +
encrypted-at-rest + bring-your-own-cloud privacy model.

## 2. What we're borrowing from Diarium

Diarium's identity rests on five pillars. This is which ones we chase and how
they translate to a Mac-native, single-developer app.

| Diarium pillar | Our take on macOS | Phase |
|---|---|---|
| **Auto-assembled days** (photos, calendar, fitness, social, location, weather) | Reframed around *Apple-native* sources: Photos, Calendar, Reminders, Maps/CoreLocation, WeatherKit, HealthKit-via-export. No third-party social APIs. | 2 |
| **Context tags** (location, weather, mood, tags, people, tracker tags) | All of it. Mood = star rating; tracker tags = custom quantified metrics you can graph. | 1–2 |
| **Views** (calendar, map, timeline, search, statistics) | All of it, built on the Timeliner timeline/dashboard patterns. | 1–2 |
| **Privacy** (app-lock, local-by-default, optional encrypted BYO-cloud sync) | App-lock (password + Touch ID), encrypted-at-rest DB, optional sync via iCloud Drive / a user-chosen folder. | 1 (lock) → 3 (sync) |
| **Import/export** (Day One/Journey/…; docx/txt/html/json) | Export to Markdown/HTML/PDF/JSON (lean on existing patterns); import from Day One + JSON. | 2–3 |

**Explicitly out of scope** (Diarium does these; we won't): native Windows
build, third-party social/fitness web integrations (Strava, Last.fm, Fitbit,
Facebook, GitHub, Untappd…), one-time-purchase storefront. These are the parts
that fit a Mac-centric, single-dev monorepo poorly. Reconsider only if the app
later moves to a Tauri stack.

## 3. Why native SwiftUI (decision recorded)

Chosen: **native macOS SwiftUI + GRDB/SQLite**, mirroring `Timeliner/`.

- Best fit for this monorepo; ~70% of the manual feature set already exists as
  reusable patterns in `Timeliner/` and `MusicJournal/`.
- Apple's frameworks (PhotoKit, EventKit, WeatherKit, CoreLocation, MapKit,
  LocalAuthentication) give us the "auto-assembled day" concept natively —
  no API keys, no OAuth dance, no backend.
- Trade-off accepted: **no Windows**, **no third-party social integrations.**
  If cross-platform parity ever becomes a hard requirement, the only path is a
  rewrite on the Tauri stack (`Molly/` is the reference) — note that up front.

## 4. Architecture (mirrors `Timeliner/`)

```
PurpleDiary/
├── Sources/PurpleDiary/
│   ├── App/          # PurpleDiaryApp, AppState, AppDelegate, Version, Info.plist, entitlements
│   ├── Models/       # GRDB records: Entry, Tag, Person, TrackerTag, TrackerValue, Attachment, Mood, AppSettings, Theme
│   ├── Services/     # DatabaseService, BackupService, SearchService, ExportService,
│   │                 #   LockService, PhotosImportService, CalendarImportService,
│   │                 #   WeatherService, LocationService, NotificationsService
│   ├── Views/        # ContentView (HStack sidebar), EntryEditor, CalendarView,
│   │                 #   MapView, TimelineView, DashboardView, OnThisDayView, Settings/
│   └── Resources/    # Assets.xcassets (AppIcon), sample data
├── Tests/PurpleDiaryTests/
├── project.yml        # XcodeGen + GRDB dependency
├── build-app.sh       # build + install + relaunch (copy Timeliner's)
├── install.sh         # → /Applications/PurpleDiary.app
├── run-tests.sh       # xcodebuild test wrapper
├── README.md / CHANGELOG.md / USER_MANUAL.md / HANDOFF.md / INSTALL.md
```

Conventions inherited verbatim from the repo (per `CLAUDE.md`):

- **Sidebar:** manual `HStack` with fixed-width sidebar — **never**
  `NavigationSplitView`. Copy `PurpleReel`'s `ContentView` + `WindowStateGuard`.
- **Storage:** `~/Library/Application Support/PurpleDiary/diary.sqlite` + `settings.json`.
- **Auto-backup on launch:** copy `Timeliner/Services/BackupService.swift`
  verbatim → zips support dir to `~/Downloads/PurpleDiary backup/`, 14-day
  retention, 5-min debounce, plus the full Settings → Backup UI (toggle, path
  picker, retention stepper, Run Now, Test/Restore/Reveal). **Non-negotiable**
  per the auto-backup standard.
- **Migrations:** GRDB `DatabaseMigrator`, append-only & immutable. Lift the
  `migration_immutability` guard test from SideMolly.
- **Versioning:** auto-derived from git (`1.0.<commit-count>`), no manual bump.
- **Default outputs:** exports → `~/Downloads/PurpleDiary/`.

## 5. Data model (first cut)

- **Entry** — `id` (UUID), `date` (ISO-8601), `title`, `bodyMarkdown`,
  `moodRating` (0–5, 0 = unset), `createdAt`, `updatedAt`,
  `latitude`/`longitude`/`placeName` (nullable), `weatherSummary`/`tempC`
  (nullable), `wordCount`. Multiple entries per day allowed.
- **Tag** / **EntryTag** — named tags with color (join table).
- **Person** / **EntryPerson** — people mentioned (mirror Timeliner's Person).
- **TrackerTag** — a user-defined quantified metric (name, unit, type:
  number/duration/bool, color).
- **TrackerValue** — `entryId` + `trackerTagId` + `value` (the per-entry datum
  we graph over time).
- **Attachment** — polymorphic BLOB (photo/video/audio/file) on an entry, 25 MB
  cap, auto-thumbnail. Copy Timeliner's `Attachment` + `AttachmentService`.
- **AppSettings** — theme, font slots, backup config, lock config, writing-goal
  word count, default output path, auto-import toggles.

## 6. Phased roadmap

### Phase 1 — MVP (manual journal + privacy core)
The blank-page journal that's genuinely usable day one. No integrations yet.

- ✅ Entry CRUD with a **Markdown editor** + native spellcheck; multiple entries
  per day; live word count (daily-goal indicator pending).
- ✅ **Tags, people, mood star-rating** on entries.
- ✅ **Calendar view** (month grid, days with entries marked) + **chronological
  timeline** + entry list.
- ✅ **Search** across title/body/tags/people (`SearchService` ranking).
- ✅ **App-lock**: passphrase + Touch ID via `LocalAuthentication`;
  lock-on-launch and lock-on-background. **Encryption-at-rest** via SQLCipher
  (whole-DB, vendored GRDB+SQLCipher). Plus a 24-word BIP39 recovery key.
- ✅ **Auto-backup on launch** + full Backup settings UI (standard).
- ✅ **Security & Privacy whitepaper** (`Docs/SECURITY.md`), readable in-app via
  Help → Security & Privacy whitepaper… — mirrors PurpleLife's, rewritten for
  PurpleDiary's local-only/no-cloud model and the 24-word recovery key.
- Themes + per-slot fonts (copy Timeliner's theme/font system).
- Sample entries seeded on first launch (so it's not empty).
- Test suite: migration round-trip + immutability guard, model Codable,
  search ranking, backup debounce/retention, lock logic.

### Phase 2 — Auto-assembled days + richer context (the Diarium signature)
- ✅ **Photos import** (PhotoKit): "Add photos from this day" suggests the photos
  taken on the entry's date and attaches the chosen ones, stored as
  SQLCipher-encrypted BLOBs in the database (downscaled, deduped by asset).
- **Calendar + Reminders import** (EventKit): pull the day's events/completed
  reminders as entry context.
- **Location + Map view** (CoreLocation + MapKit): geotag entries, browse them
  on a map.
- **Weather** (WeatherKit): record conditions, temp, sunrise/sunset, moon phase
  for the entry's date+place.
- ✅ **Tracker tags + graphs**: define custom metrics (number+unit / duration /
  yes-no), log per entry, plot daily-average trends in the dashboard (Swift
  Charts). Trackers section + entry-editor logging row + per-tracker Insights
  chart; included in JSON/Markdown/HTML export.
- ✅ **Statistics/insights dashboard** (Insights section): word counts, streaks,
  mood-over-time, entries/words-per-month, tag usage (Swift Charts), plus a
  per-tracker line chart.
- ✅ **Export**: Markdown / HTML / PDF (Timeliner's `ExportService`
  HTML→WKWebView→PDF pipeline) / JSON — whole-journal, grouped by month, from
  File → Export Journal… or Settings → General. JSON is versioned + round-trippable.

### Phase 3 — Memory, sync, migration
- **"On this day"** flashback view + opt-in `UNUserNotificationCenter`
  reminders (copy Timeliner's NotificationsService).
- **Journaling reminders** (daily nudge at a configurable hour).
- **Bring-your-own-cloud sync**: simplest first cut = point the DB/backup at an
  iCloud Drive or user-chosen folder; encrypted-at-rest means the synced file
  is already protected. (Full multi-device conflict resolution is a stretch goal.)
- **Import** from Day One (JSON/zip) and our own JSON export.

## 7. Key decisions still open (for later, not blockers)

1. **Encryption mechanism** — SQLCipher (whole-DB, transparent, needs the
   SQLCipher build of GRDB) vs. app-managed envelope encryption like PurpleIRC's
   `EncryptedJSON`/`KeyStore`. SQLCipher is cleaner for a SQLite-centric app.
2. **WeatherKit entitlement** — requires an Apple Developer account + a service
   ID; fine for the maintainer's signing setup but adds a provisioning step.
3. **Sync depth** — "file in a synced folder" (cheap, good enough for
   single-user multi-Mac) vs. true CloudKit sync (Timeliner's own Phase-3
   stretch goal). Recommend starting with the former.
4. **Historical photo/health import** — HealthKit has no macOS API; fitness data
   would come from a manual Health export, if at all. Likely defer indefinitely.

## 8. Reuse map (what to copy from where)

| Need | Copy from |
|---|---|
| Sidebar layout + window-state guard | `PurpleReel/.../ContentView.swift`, `WindowStateGuard.swift`, `AppDelegate.swift` |
| Launch-time backup + Settings UI | `Timeliner/.../Services/BackupService.swift` + Settings → Backup tab |
| Markdown editor w/ toolbar + spellcheck | `MusicJournal/.../Views/MarkdownEditor.swift` |
| Polymorphic BLOB attachments + thumbnails | `Timeliner/.../Attachment.swift`, `AttachmentService.swift` |
| Vertical timeline, dashboard, themes, fonts | `Timeliner/.../TimelineView.swift`, `DashboardView.swift`, `Theme.swift`, `FontStyle.swift` |
| Search ranking | `Timeliner/.../Services/SearchService.swift` |
| HTML→PDF export pipeline | `Timeliner/.../Services/ExportService.swift` |
| Notifications / anniversaries | `Timeliner/.../Services/NotificationsService.swift` |
| Migration immutability test | `SideMolly/src-tauri/src/lib.rs::migration_immutability` (Swift port) |
| build/install/test/project.yml scaffolding | `Timeliner/` (closest sibling) |

## 9. Suggested first commit (when greenlit)

Scaffold Phase-1 skeleton: `project.yml`, build/install/test scripts, `App/`
entry point + AppState + AppDelegate + WindowStateGuard, the `Entry`/`Tag`/
`Person`/`Mood` models + `DatabaseService` with migration `v1_initial`, a
minimal `ContentView` (HStack sidebar → calendar + entry list + editor), and
`BackupService`. That alone is a runnable, backed-up, lockable journal —
everything after is additive.
