# PeekServer

A small **LAN media-review service** — review "NEW … TO REVIEW" media folders **fast, from any
Mac or iPad** on the local network. It's the client-server companion to the PurplePeek macOS app,
built for the case where the media lives on **slow/remote storage** (a spinning external on the
"airy" runner) and you want to triage from multiple machines.

Why it's fast and multi-device:

- **Cached thumbnails.** Thumbnails are generated once (macOS `sips`/`qlmanage`) and cached on the
  server's local disk, then served to every client. Browsing reads tiny JPEGs — it never touches
  the big originals off slow/remote storage. Originals are fetched only when you open or keep one.
- **One authoritative decisions DB.** Keep/skip/favorite/title/caption/keywords/albums live in a
  single server-side SQLite DB, so review state is **shared across every client instantly** — no
  per-Mac databases to reconcile.
- **Zero dependencies.** Pure Python **stdlib** + macOS native tools. Nothing to `pip install`,
  so it deploys cleanly to the runner.

It runs on whichever host has the media attached — **Vortex now (REDONE is local), the airy runner
later** (host-agnostic; just move the drive + the config).

## Run

```bash
cp config.example.json config.json   # then edit "roots"
./run.sh                              # → http://<host>:8788  (open from any Mac/iPad)
```

`config.json` (gitignored — may carry local paths):

| key | meaning |
|---|---|
| `port` / `bind` | listen port; `0.0.0.0` = reachable from the LAN |
| `dbPath` | the decisions database |
| `thumbCache` | where generated thumbnails are cached |
| `thumbSize` | max thumbnail dimension (px) |
| `scanIntervalMinutes` | auto-rescan every N min so newly-staged files appear without a manual scan (default 15; `0` = scan only at startup) |
| `proxyCache` / `ffmpegBin` / `proxyHeight` / `proxyMaxBitrateK` / `warmProxies` | video streaming proxies: each video is transcoded once (`ffmpeg` → 720p faststart, bitrate-capped MP4) and served at `/preview/<id>` for smooth LAN playback. Needs `ffmpeg` (`brew install ffmpeg`); falls back to the original if absent. |
| `roots` | `[{path,label,kind}]` — the review folders to serve |
| `authUser` / `authPasswordSHA256` | Basic Auth (both empty = open). Store only the SHA-256 hash. |

**Auth.** The service gates every request with HTTP Basic Auth when `authUser` + `authPasswordSHA256`
are set (the plaintext password is never stored). Generate a hash:
`python3 -c 'import hashlib,getpass;print(hashlib.sha256(getpass.getpass().encode()).hexdigest())'`

**Warm the cache first** (especially on slow/remote storage): `./run.sh --warm` pre-generates all
thumbnails with a worker pool, so the first browse reads tiny cached thumbs, not the big originals.

## Review UI

A keyboard-driven thumbnail grid (open `/` in a browser):

- `↑ ↓ ← →` move · `K` keep · `X` skip · `F` favorite · `U` undecide · `↵` open detail · `Esc` close
- Filter tabs: Undecided / Kept / Skipped / Favorites / All; switch review folders top-left.
- Detail overlay: full image/video + editable title, caption, keywords, albums.

## API

`GET /api/roots` · `GET /api/items?root&decision&offset&limit` · `GET /api/item/<id>` ·
`GET /thumb/<id>` · `GET /full/<id>` (Range-aware) · `POST /api/decision` · `POST /api/scan`

## Keep → Photos (Phase 2)

Once you've triaged, run the worker on the host with the Photos library:

```bash
./run.sh --migrate-purplepeek   # one-time: pull existing PurplePeek decisions into the DB
./run.sh --import               # DRY-RUN: shows what would import/trash/export
./run.sh --import --execute     # actually do it
```

- Keepers → `osxphotos import` (title/description/keyword/album on the asset; favorites via a
  staged copy with `exiftool` `XMP:Rating` + `--favorite-rating`).
- Kept audio → keep-exported to `keptAudioDir` (Photos can't hold audio).
- Skips → moved to the Trash (recoverable; needs Finder Automation permission on the host).

`process_pending` is **dry-run by default** — nothing imports or trashes without `--execute`.

## Status / roadmap

- **Phase 1:** scan + cached thumbnails + decisions DB + the web review UI. ✅
- **Phase 2:** keep→Photos import worker (`exiftool` + `osxphotos import`), kept-audio export,
  skip→Trash, and PurplePeek decision migration. ✅
- **Phase 3:** deploy to airy (launchd agent; move REDONE + config). ◻️
