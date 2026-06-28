# Changelog

## 0.3.0 — Auth + fast browsing

- **HTTP Basic Auth** (`auth.py`) gates every request, so the service isn't open on the LAN. The
  password is stored only as a **SHA-256 hash** in the local (gitignored) config; comparison is
  constant-time. Both `authUser`/`authPasswordSHA256` empty = open (back-compat). Set them in
  `config.json` (a hash one-liner is in `config.example.json`).
- **Parallel thumbnail warm** — `--warm` now generates thumbnails with a worker pool
  (`warmWorkers`, default 6) instead of serially, overlapping the slow per-file reads. This is the
  fix for "unusably slow" first-browse on a slow/remote drive: warm once, then browsing reads tiny
  cached thumbs instead of the big originals. (10 auth/warm-related additions; 19 tests total.)

## 0.2.0 — Phase 2 (keep→Photos import + migration + warm-up)

- **Import worker** (`importer.py`) — the keep→Photos pipeline, delegating to proven tools on the
  Photos host: keepers → `osxphotos import` with title/description/keyword/album set on the asset
  (favorites staged with an exiftool-embedded `XMP:Rating` + `--favorite-rating`); kept audio →
  keep-export to `keptAudioDir` (Photos can't hold audio); skips → Trash (recoverable). The argv
  builder is pure/unit-tested; `process_pending` **defaults to DRY-RUN** (nothing imports/trashes
  without `--execute`).
- **PurplePeek decision migration** (`migrate.py`) — copies existing keep/favorite/title/caption/
  keywords/albums from `purplepeek.sqlite` into PeekServer's DB, matched by file path (idempotent).
- **`--warm`** — scan + pre-generate every thumbnail (the one-time cold-cache pass), so the first
  browse is already fast. CLI: `--warm`, `--migrate-purplepeek [DB]`, `--import [--execute] [--limit N]`.
- **API:** `POST /api/migrate`, `POST /api/process` (dry-run unless `{"execute":true}`).
- New config: `osxphotosBin`, `exiftoolBin`, `keptAudioDir`, `stagingDir`, `purplePeekDb`.
- DB: `mark_imported/exported/deleted`, `pending_imports/audio/skips`.
- Tests: +5 (import argv incl. favorite, migration mapping + path-matching, dry-run worker) → 13 total.

## 0.1.0 — Phase 1 (LAN review MVP)

- New subproject: a dependency-free (Python stdlib + macOS `sips`/`qlmanage`) HTTP service for
  reviewing "NEW … TO REVIEW" media folders fast from any Mac/iPad on the LAN.
- **Scanner** (`scan.py`) walks configured roots → SQLite, decision-safe on re-scan (preserves
  keep/skip/metadata; marks vanished files missing).
- **Decisions DB** (`db.py`) mirrors PurplePeek's schema (keep, favorite, title, caption,
  keywords, albums, hidden) — one authoritative server-side store shared by all clients.
- **Thumbnails** (`media.py`) generated once via `sips` (images, incl. HEIC) / `qlmanage` (video
  posters) and cached on the server's local disk → browsing never reads the big originals.
- **HTTP server** (`server.py`, stdlib): web UI + JSON API + `/thumb` (cached) + `/full`
  (Range-aware, so video plays in-browser).
- **Web UI** (`web/`): keyboard-driven thumbnail grid (K/X/F/U), filter tabs with live counts,
  per-root switching, detail overlay with full media + editable title/caption/keywords/albums.
- `config.example.json` committed; real `config.json` gitignored (may carry local paths).
