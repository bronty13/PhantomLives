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
| `roots` | `[{path,label,kind}]` — the review folders to serve |

## Review UI

A keyboard-driven thumbnail grid (open `/` in a browser):

- `↑ ↓ ← →` move · `K` keep · `X` skip · `F` favorite · `U` undecide · `↵` open detail · `Esc` close
- Filter tabs: Undecided / Kept / Skipped / Favorites / All; switch review folders top-left.
- Detail overlay: full image/video + editable title, caption, keywords, albums.

## API

`GET /api/roots` · `GET /api/items?root&decision&offset&limit` · `GET /api/item/<id>` ·
`GET /thumb/<id>` · `GET /full/<id>` (Range-aware) · `POST /api/decision` · `POST /api/scan`

## Status / roadmap

- **Phase 1 (this):** scan + cached thumbnails + decisions DB + the web review UI. ✅
- **Phase 2:** the keep→Photos **import worker** — delegates to `exiftool` + `osxphotos import`
  (metadata + albums + favorite via PhotoKit) on the host with the Photos library; skips → Trash;
  audio → keep-export. Migrate existing PurplePeek decisions in.
- **Phase 3:** deploy to airy (launchd agent; move REDONE + config).
