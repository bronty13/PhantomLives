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
- ❌ **Weather** (WeatherKit): **dropped — out of scope.** Implemented against the
  WeatherKit REST API, then reverted: it requires sending the entry's
  coordinates to Apple over the network, which breaks PurpleDiary's no-network /
  local-first guarantee. Not pursued unless that posture is explicitly revisited.
  (A fully-offline manual "conditions" field remains a possible future
  alternative, using the reserved `weatherSummary`/`tempC` columns.)
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

### Phase 3+ build-out (Day One–parity, privacy-respecting) — supersedes the framing above

After a feature comparison against Day One, Diarium, Journey, Diaro, Apple
Journal, and Obsidian, the post-Phase-2 work is re-planned as the phases below.
Every item is **fully on-device** (no network); explicitly avoided as
network-dependent: cloud sync, web app, live weather, map tiles, AI-over-entries,
fitness/social integrations. Each phase is its own build/test/PR.

| Phase | Scope | Status |
|---|---|---|
| **3 — Journals** | Multiple journals; **hidden/locked** journals (Option A: app-level visibility gate — filtered out of Timeline/Calendar/Search/Insights until unlocked for the session). Sidebar switcher, per-entry journal, move-between, export schema v4. | ✅ **done** |
| **4 — Reflection** | "On This Day" flashback (local date query) + a **bundled static** prompt library rotating daily. | ✅ **done** |
| **5 — Templates** | Reusable entry scaffolds with auto-filled date. | ✅ **done** |
| **6 — Calendar heatmap + reminders** | Word-count intensity on the calendar; local `UNUserNotificationCenter` daily reminder. | ✅ **done** |
| **7 — Attachments+** | PDF / document / any-file attachments (PDFKit reader + thumbnail). Extends the encrypted-BLOB model. **Drawing deferred** — PencilKit isn't a native-macOS fit. | ✅ **done** (drawing deferred) |
| **8 — Importers** | PurpleDiary round-trip + Day One / Diarium / Journey JSON import (file-based, offline). | ✅ **done** |
| **9 — Vault (Option B)** | Per-journal **cryptographic** separation: a hidden journal sealed under its own passphrase-wrapped key (AES-GCM), opaque even with the app open. Borrows PurpleLife's vault pattern. The last pole. | ✅ **shipped** — `v6_vault` + `VaultService` crypto core, transparent seal-on-write/unseal-on-read in `DatabaseService`, locked-vault visibility/export gate, vault-aware moves, and the Make-Vault / unlock / change-passphrase / remove UI in the sidebar; app-lock re-seals vaults; +20 tests. v1 seals titles+bodies (attachment-byte sealing is the one documented fast-follow) |

### Phase 9 — Vault: locked design (build as a focused, self-contained PR)

A **vault journal** is a journal whose entry **titles, bodies, and attachment
bytes** are sealed under a per-journal content key — ciphertext **even when the
app is open and SQLCipher is unlocked** — until the user enters that journal's
passphrase for the session. This is strictly stronger than Phase-3 "hidden"
(which is only a visibility filter). Confirmed decisions:

- **Key model — per-journal passphrase.** Each vault journal has a random
  256-bit **content key (CK)**. CK is wrapped two ways and stored in a
  `vault_envelopes` row per journal: (1) by a **passphrase-derived KEK**
  (PBKDF2-HMAC-SHA256, per-journal salt, 300k iters → AES-256-GCM wrap), and
  (2) by a **recovery-key-derived KEK** (from the existing 24-word phrase) so a
  lost passphrase isn't permanent lockout. Reuse `Crypto` (AES-GCM + PBKDF2) and
  `RecoveryKey`.
- **Recovery — also wrapped under the 24-word key.** Creating a vault therefore
  needs the recovery phrase once (to make the recovery wrap). Document that the
  recovery phrase is a master key for vaults too.
- **Export/backup.** The launch **backup keeps ciphertext** automatically — the
  DB it zips already holds CK-sealed blobs + the `vault_envelopes`, so a restore
  + passphrase (or recovery phrase) reopens it; no special backup code needed.
  **Export (MD/HTML/PDF/JSON) skips locked vault journals** (only emits unlocked
  content). This *changes* today's Phase-3 behavior where export includes hidden
  journals — update `SECURITY.md` accordingly.

Implementation outline:
- **Migration v6_vault**: `vault_envelopes` (`journal_id` PK, `salt`, `iters`,
  `pass_wrap` BLOB, `recovery_wrap` BLOB) + `journals.is_vault` (default 0).
- **VaultService**: createVault(journalId, passphrase, recoveryWords) → random
  CK, write both wraps; unlock(journalId, passphrase|recoveryWords) → CK held in
  a session-only in-memory map; changePassphrase; removeVault (decrypt-in-place).
- **Transparent crypto at the data layer**: when an entry belongs to a locked
  vault journal, its `title`/`body_markdown` (and attachment `data`/`thumbnail`)
  are stored as CK-AES-GCM ciphertext with a sentinel prefix; `DatabaseService`
  encrypts on write and decrypts on read **only when CK is in scope**. Reads of a
  locked vault entry return sealed placeholders (never plaintext). This is the
  highest-risk surface — needs exhaustive round-trip + "locked returns
  ciphertext" + "wrong passphrase fails" tests before merge.
- **UI**: a journal context-menu "Make Vault…" (set passphrase + confirm
  recovery phrase); the sidebar lock flow routes vault journals through a
  passphrase prompt (not just Touch ID); Settings → Security shows vault status.
- **Guardrails**: all-or-nothing per PR (no half-migrated state); a vaulted
  entry must be decryptable by either the passphrase or the recovery phrase
  before the encrypting write commits.

The original "Phase 3 — Memory, sync, migration" bullets fold in here:
On-This-Day/reminders → Phases 4 & 6; Day One import → Phase 8;
bring-your-own-cloud sync remains **deferred** (a synced encrypted file is
already protected, but conflict resolution is out of scope for now).

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
