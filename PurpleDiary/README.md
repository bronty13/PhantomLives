# PurpleDiary

A native macOS SwiftUI journaling app inspired by [Diarium](https://diariumapp.com).
Local-first, private, no account, **no network** — your journal lives in a single
SQLite database on your Mac. See [SCOPING.md](SCOPING.md) for the design brief and
roadmap, [HANDOFF.md](HANDOFF.md) for the architecture snapshot, and
[Docs/SECURITY.md](Docs/SECURITY.md) for the security model.

> **Status:** Phase 1 complete (core journal + privacy core: encryption-at-rest,
> app-lock, 24-word recovery key). Phase 2 shipped: **Insights**, **export**,
> **trackers**, and **media** (Photos import + filesystem photo/video/audio
> import + in-app viewer/player). Phase 3 shipped: **journals** (multiple +
> hidden). Phase 4 shipped: **reflection** (On This Day + writing prompts).
> Phase 5 shipped: **templates**. Phase 6 shipped: **calendar heatmap + daily
> reminder**. Phase 7 shipped: **PDF & file attachments**. Phase 8 shipped:
> **importers** (PurpleDiary / Day One / Journey / Diarium JSON). Phase 9 (a
> per-journal encryption **vault**) is roadmapped in SCOPING.md.
> Network-based auto-context (e.g. WeatherKit) is **out of scope** — PurpleDiary
> stays fully offline. See SCOPING.md / HANDOFF.md.

## At a glance (Phase 1)

- **Entries** — Markdown body, optional title, editable date/time, multiple
  entries per day. Live word count. **Import…** in the editor toolbar pulls a
  Markdown/text/RTF file's contents into the body (smart merge — sets an empty
  body, or appends after a `---` separator). *(Phase 2)*
- **Journals** — keep separate notebooks; each entry belongs to one. Pick **All
  Journals** or focus a single one from the sidebar. Mark a journal **Hidden** to
  lock it out of the Timeline, Calendar, Search, and Insights until you unlock it
  (Touch ID / passphrase) for the session. *(Phase 3)*
- **Mood** — 0–5 star rating per entry.
- **Tags** — named, colored, toggleable per entry; six seeded on first launch.
- **People** — a global list of recurring people you can link to entries.
- **Timeline** — entries grouped by month, newest first, with an inline editor.
- **Calendar** — month grid shaded as a **heatmap** by how much you wrote each
  day; click to jump or create. *(heatmap: Phase 6)*
- **Search** — ranked across title / body / tags / people.
- **On This Day** — entries from today's date in previous years, grouped by "N
  years ago." A local look-back; nothing fetched. *(Phase 4)*
- **Writing prompts** — an empty entry offers a daily prompt from a bundled
  library (Use to drop it in, shuffle for another). On-device, no network.
  *(Phase 4)*
- **Templates** — reusable entry scaffolds with auto-filled date tokens. Start
  one from the New Entry split-menu; manage them in **Manage Templates…**.
  *(Phase 5)*
- **Daily reminder** — an opt-in local notification at a time you pick (Settings →
  Reminders). On-device, no network. *(Phase 6)*
- **Import** — bring entries in from a JSON export (PurpleDiary's own, Day One,
  Journey, or Diarium) via File → Import Journal… (⇧⌘I). Additive; nothing
  overwritten. *(Phase 8)*
- **Photos, video & audio** — "Add from Photos" pulls in the photos you took on
  the entry's date (PhotoKit), with a date picker to browse any other day and a
  "Show all recent" toggle for the whole library. "Add from Files…" imports
  photos, **videos**, and **audio** from anywhere on your Mac. Click any
  thumbnail to view it full-size (image), play it (video, AVKit), or play it in a
  compact transport (audio). All media is stored as SQLCipher-encrypted BLOBs in
  the database — photos downscaled, video and audio byte-for-byte. **PDFs** (with
  a PDFKit reader) and **any other file** can be attached too. *(Phase 2 / 7)*
- **Trackers** — define custom quantified metrics (number + unit, duration, or
  yes/no), log them per entry, and graph the trend. *(Phase 2)*
- **Insights** — Swift Charts dashboard over your entries: summary cards
  (entries, words, days journaled, avg mood, current/longest streak), mood over
  time, entries/words per month, tag usage, and a line chart per tracker. No new
  permissions. *(Phase 2)*
- **Export** — save the whole journal as **Markdown**, **HTML**, **PDF**, or
  **JSON** from File → Export Journal… (⇧⌘E) or Settings → General. Entries are
  grouped by month; files land in `~/Downloads/PurpleDiary/`. JSON is a
  versioned, round-trippable dump (now schema v3, including trackers and
  per-entry photo counts) for backup/re-import. *(Phase 2)*
- **Auto-backup at every launch** — zips the support directory to
  `~/Downloads/PurpleDiary backup/` with 14-day retention; verify and restore
  from Settings → Backup. (PhantomLives convention.)
- **Encryption at rest** — the whole `diary.sqlite` is SQLCipher-encrypted
  (AES-256). The data key lives in the login Keychain; a one-shot
  `sqlcipher_export()` migration upgrades an existing plaintext DB on first
  launch (the launch backup captures the plaintext first).
- **App-lock** — optional lock screen (Touch ID / device password / passphrase),
  lock-on-launch, lock-on-background, ⌘L. Configured in Settings → Security.
- **24-word recovery key** — BIP39 phrase shown on first launch; unlocks the DB
  if the Keychain entry is ever lost. No cloud involved.
- **Security & Privacy whitepaper** — a full trust document
  ([`Docs/SECURITY.md`](Docs/SECURITY.md)) readable in-app via **Help → Security
  & Privacy whitepaper…**. Covers the encryption-at-rest design, the recovery
  key, the local-only/no-network model, and a "verify the claims" section, and
  is honest about limitations (`settings.json` is plaintext preferences only).

## Build

```sh
./build-app.sh          # build + install to /Applications + relaunch
./build-app.sh --no-open
./build-app.sh --no-install   # build only
```

The build script regenerates `PurpleDiary.xcodeproj` from `project.yml` via
`xcodegen`, generates the app icon programmatically
(`Scripts/generate-icon.swift`), builds Release in `/tmp` (avoids iCloud xattr
issues), signs with your Developer ID if present (ad-hoc otherwise), then
hands off to `install.sh`.

Version is auto-derived from git: `1.0.<commit-count>` for
`CFBundleShortVersionString`, `<count>.<short-sha>` for `CFBundleVersion`. No
manual version bumping.

**Requires full Xcode** (not just Command Line Tools) and `xcodegen` on PATH.

## Test

```sh
./run-tests.sh          # xcodebuild test → PurpleDiaryTests
```

Test suite covers GRDB migrations + cascade behavior, model Codable/word-count,
search ranking, BackupService debounce/retention/verify, and the privacy core:
AES-GCM crypto, BIP39 recovery-key encode/decode/checksum, KeyStore
passphrase/recovery unlock round-trips, SQLCipher at-rest (ciphertext on disk,
wrong-key rejection, plaintext→SQLCipher migration), the sample-data facility,
the Insights stats aggregation (including tracker series), tracker + attachment
migrations / cascade / Codable, image downscaling + thumbnailing, and the
Markdown/HTML/JSON export render paths.

## Encryption & dependencies

GRDB and SQLCipher 4.6.1 are **vendored** under `Vendor/` (local SwiftPM
packages) — there's no Homebrew or OpenSSL requirement. SQLCipher's `sqlite3_*`
symbols shadow the system `libsqlite3.dylib` at link time (SQLCipher is listed
before GRDB in `project.yml`, and GRDB's `CSQLite` is patched to re-export the
vendored header), so a `PRAGMA key` on every connection encrypts the whole
database. See `Vendor/SQLCipher/PROVENANCE.md`.

## Project layout

```
PurpleDiary/
├── Sources/PurpleDiary/
│   ├── App/          # PurpleDiaryApp, AppState, AppDelegate, AppMenuCommands, Version, Info.plist
│   ├── Models/       # Entry, Mood, Tag, Person, TrackerTag, Attachment, AppSettings (GRDB records)
│   ├── Services/     # DatabaseService(+SQLCipher), BackupService, SearchService, SampleDataService,
│   │                 #   ExportService, ImageProcessing, PhotosImportService, KeyStore, KeychainStore,
│   │                 #   Crypto, RecoveryKey, BIP39Wordlist, BootState, BiometricAuthService,
│   │                 #   StatsService, WindowStateGuard
│   └── Views/        # ContentView (HStack sidebar), Timeline, EntryEditor, Calendar, Insights, Search,
│                     #   People, Tags, Trackers, PhotoImport, ExportSheet, AppLockScreen, RecoveryScreen,
│                     #   RecoveryKeySaveSheet, SecurityDocView, Settings/, Shared/
├── Tests/PurpleDiaryTests/
├── Vendor/           # GRDB.swift + SQLCipher 4.6.1 (local SwiftPM packages)
├── Scripts/generate-icon.swift
├── project.yml · build-app.sh · install.sh · run-tests.sh
```

## Default output locations

| Kind | Location |
|---|---|
| Database | `~/Library/Application Support/PurpleDiary/diary.sqlite` |
| Settings | `~/Library/Application Support/PurpleDiary/settings.json` |
| Backups | `~/Downloads/PurpleDiary backup/PurpleDiary-yyyy-MM-dd-HHmmss.zip` |
| Exports | `~/Downloads/PurpleDiary/PurpleDiary-Journal-<stamp>.{md,html,pdf,json}` |

All output paths are user-overridable in Settings; the override persists.
