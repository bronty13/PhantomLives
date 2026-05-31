# PurpleDiary

A native macOS SwiftUI journaling app inspired by [Diarium](https://diariumapp.com).
Local-first, private, no account — your journal lives in a single SQLite
database on your Mac. See [SCOPING.md](SCOPING.md) for the full design brief and
phased roadmap.

> **Status:** Phase 1. The core journal (write, browse, search, tag, mood,
> backup) plus the **privacy core** — encryption-at-rest, app-lock, and a 24-word
> recovery key — are in place. Auto-assembled days (Photos/Calendar/WeatherKit),
> tracker tags, map view, and sync are scoped for later phases — see SCOPING.md.

## At a glance (Phase 1)

- **Entries** — Markdown body, optional title, editable date/time, multiple
  entries per day. Live word count.
- **Mood** — 0–5 star rating per entry.
- **Tags** — named, colored, toggleable per entry; six seeded on first launch.
- **People** — a global list of recurring people you can link to entries.
- **Timeline** — entries grouped by month, newest first, with an inline editor.
- **Calendar** — month grid; days with entries are dotted; click to jump or
  create.
- **Search** — ranked across title / body / tags / people.
- **Insights** — Swift Charts dashboard over your entries: summary cards
  (entries, words, days journaled, avg mood, current/longest streak), mood over
  time, entries/words per month, and tag usage. No new permissions. *(Phase 2)*
- **Export** — save the whole journal as **Markdown**, **HTML**, **PDF**, or
  **JSON** from File → Export Journal… (⇧⌘E) or Settings → General. Entries are
  grouped by month; files land in `~/Downloads/PurpleDiary/`. JSON is a
  versioned, round-trippable dump for backup/re-import. *(Phase 2)*
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
the Insights stats aggregation, and the Markdown/HTML/JSON export render paths.

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
│   ├── Models/       # Entry, Mood, Tag, Person, AppSettings (GRDB records)
│   ├── Services/     # DatabaseService(+SQLCipher), BackupService, SearchService, SampleDataService,
│   │                 #   KeyStore, KeychainStore, Crypto, RecoveryKey, BIP39Wordlist,
│   │                 #   BootState, BiometricAuthService, StatsService, WindowStateGuard
│   └── Views/        # ContentView (HStack sidebar), Timeline, EntryEditor, Calendar, Insights, Search,
│                     #   People, Tags, AppLockScreen, RecoveryScreen, RecoveryKeySaveSheet, Settings/, Shared/
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
