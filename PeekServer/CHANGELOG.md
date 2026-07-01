# Changelog

## 0.5.2 — Parallel proxy warm

- **Warm transcodes several videos at once** (`warmConcurrency`, default 3) instead of one-at-a-time,
  so a review-queue backlog of proxies clears in a fraction of the time — the videos you're about to
  review are ready before you reach them. Videos still needing a proxy are collected in `warmOrder`
  priority, then transcoded through a small thread pool.

## 0.5.1 — `/preview` never blocks the player

- **Fixes the Preview-tab inline player spinning on un-warmed videos.** `/preview` used to run the
  transcode **synchronously** on a cache miss, so the streaming player (`AVPlayer` over HTTP) sat
  waiting for the whole transcode — spinning, sometimes for minutes on a large 4K clip — while the
  Browse-tab spacebar (QuickLook, which uses `/full`) played fine. Now `/preview` is **non-blocking**:
  it serves the cached proxy if ready (instant, smooth), else **kicks the transcode in the background
  and serves the original immediately** so the player starts right away (like `/full`), and the next
  view gets the fast proxy. `ensure_video_proxy_async` (deduped per destination) does the background
  kick. The background warm still front-fills proxies so most views hit the fast path.

## 0.5.0 — Video streaming proxies (smooth review playback)

- **Videos now stream via a cached 720p faststart proxy** instead of the full-resolution original.
  Full-res clips (4K, tens of Mbps) don't stream smoothly to a review client over LAN/Wi-Fi — the
  player stalls ~20–30 s fetching the `moov` index and then can't keep up with the bitrate. Like
  thumbnails, each video is now transcoded **once** (`ffmpeg` → 720p, H.264 veryfast/CRF 26, hard
  bitrate cap, AAC, `+faststart`) to a disk-cached MP4 and served from a new **`GET /preview/<id>`**
  endpoint: instant start, smooth playback. The full original stays at `/full` for the actual import.
- **Warm-ahead:** `--warm` now also generates video proxies, and every scan kicks a throttled
  background proxy-warm (`warmProxies`, default on) so newly-staged videos are ready to play without
  a first-view transcode stall. On-demand generation (serialized per file) covers anything not warmed.
- **Warm order is configurable** (`warmOrder`): a priority list of substrings matched against each
  root's path/label — matches warm first, the rest last. Keeps the active, fast-drive roots (Rachel's
  new-items-to-review on the SSD) ahead of a big slow-drive backlog (the "My Photos" root on the SMR
  REDONE), so review videos get proxies first instead of waiting behind hours of backlog transcoding.
- **launchd/TCC fix:** third-party ffmpeg has no removable-volume TCC grant, so under the launchd
  server its `open()` of a file on an external volume *hangs* on a consent prompt it can't show
  (0% CPU, no output — Apple's sips/qlmanage are exempt, so thumbnails were unaffected). The proxy
  generator now **stages the source to internal disk first** (this process can read externals — it
  serves `/full`) and transcodes locally, so ffmpeg never touches the volume.
- New config: `proxyCache`, `ffmpegBin`, `proxyHeight` (720), `proxyMaxBitrateK` (4000), `warmProxies`, `warmOrder`.
  **Requires `ffmpeg`** (`brew install ffmpeg`); if it's missing or a transcode fails, `/preview`
  falls back to the original so playback still works (just not accelerated). Pure command builder
  (`ffmpeg_proxy_args`) + proxy path are unit-tested (26 tests).

## 0.4.0 — Periodic auto-rescan

- **Auto-rescan on an interval** (`scanIntervalMinutes`, default **15**; `0` disables). Previously
  PeekServer scanned roots only at startup or on an explicit `POST /api/scan`, so files staged
  *after* launch (e.g. Rachel's hourly photo sync into `NEW PHOTOS TO REVIEW`) never appeared in
  clients until someone manually triggered a scan — the review queue silently went stale. A daemon
  thread now rescans every root every N minutes; `background_scan()`'s existing overlap guard means a
  slow scan just skips the next tick instead of piling up. `periodic_scan_interval()` is pure and
  unit-tested. Set `scanIntervalMinutes` in `config.json`. (Incident: airy's Rachel photos scanned at
  03:16 and nothing newer showed for hours despite the sync staging batches hourly.)

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
