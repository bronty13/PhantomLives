# applemusic-complete-playlist

Build a **complete** Apple Music playlist of one artist's catalog — every
available song by the artist, **plus** songs where they're a featured/secondary
artist ("appears-on") — and re-run to update it. The Apple Music sibling of
`../spotify-complete-playlist`.

**Why Apple Music?** Spotify's February-2026 Development-Mode lockdown (removed
batch endpoints, pagination capped at 10, restricted user endpoints, punitive
multi-hour rate-limit cooldowns) made bulk catalog work on Spotify untenable for
a personal app — see `../docs/spotify-rate-limits.md`. Apple Music has no
equivalent dev-mode crippling: rich per-artist relationship "views" and full
library-write endpoints. It even lets you **create** playlists via API (Spotify
dev-mode can't), so there's no "make the empty playlist by hand" step.

## How it works

1. Sign an **ES256 developer token** (JWT) from your MusicKit `.p8` key.
2. Authorize **once** in the browser to mint a long-lived **Music User Token**.
3. Enumerate the artist's albums (own releases + appears-on/compilation/featured
   views), expand each album to its songs, keep the right ones (all of the
   artist's own; only credited tracks from appears-on albums), dedupe by catalog
   song id.
4. Create (or idempotently append to) a **library playlist**.

Rate-limit hygiene is built in from the start (Apple doesn't publish quotas, so
they're treated as unknown): per-request **throttle**, on-disk **catalog cache**
(scan once, reuse), **fail-fast on HTTP 429** (never sleep for hours), full
**logging** to `logs/build_<ts>.log`.

## Prerequisites

- A paid **Apple Developer Program** membership (you're Account Holder of team
  `SRKV8T38CD`).
- An active **Apple Music subscription** (required for library writes).
- Python 3 (the scripts self-bootstrap a `.venv` with `requests`, `PyJWT`,
  `cryptography`).

## One-time setup

### 1. Create a MusicKit private key (.p8)

In the Apple Developer dashboard (**Account Holder/Admin** role required):

1. <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**.
2. **Identifiers** → register a **Media ID** (Media Services identifier) if you
   don't have one.
3. **Keys** → **+** → enable **MusicKit** → register → **Download** the `.p8`
   file (you can only download it once — keep it safe, e.g. `~/.secrets/`).
4. Note the **Key ID** (10 chars, shown next to the key). Your **Team ID** is
   `SRKV8T38CD`.

### 2. Configure

```bash
cp config.local.json.example config.local.json
# edit: key_id + private_key_path (team_id is already SRKV8T38CD)
```

`config.local.json` and any `*.p8` are git-ignored — secrets never get committed.

### 3. Verify the developer token (no user token needed)

Catalog reads need only the developer token, so you can confirm auth works before
the browser step:

```bash
python3 build_playlist.py --verify-token
```

Expect: `Developer token OK ✓ — catalog read returned: Taylor Swift (...)`.

### 4. Authorize once (mint the Music User Token)

```bash
python3 authorize.py
```

A browser tab opens → click **Authorize Apple Music** → sign in → allow. The
token is saved to `music_user_token.json` (git-ignored, `chmod 600`) and reused
for ~6 months. When it eventually expires, just run `authorize.py` again.

## Build a playlist

```bash
python3 build_playlist.py --artist "Taylor Swift" --playlist-name "Taylor Swift Complete [PL]"
```

It scans the catalog (cached after the first run), creates the library playlist,
and adds every song. Re-running **appends only what's missing** (idempotent), so
updating after a new release is the same command. Adds are **crash-safe**: the
local manifest is checkpointed after every 100-song batch, so if Apple throws a
transient `500 Cloud Library` mid-add, the songs that already landed are recorded
and a re-run resumes cleanly instead of risking duplicates or orphans.

Preview without writing anything:

```bash
python3 build_playlist.py --artist "Taylor Swift" --playlist-name "Taylor Swift Complete [PL]" --dry-run
```

## Options

```
--artist NAME           Artist to search for
--artist-id ID          Exact Apple Music catalog artist id (skips search)
--playlist-name NAME    Target library playlist name (created if absent)
--storefront CC         Storefront/country (default: your account's, else 'us')
--throttle SECONDS      Pause after each API request (default 0.2)
--refresh-catalog       Force a fresh scan instead of the cached catalog
--dry-run               Scan + report counts, don't create/modify the playlist
--verify-token          Just test the developer token with a catalog read
--log-dir DIR           Run-log directory (default ./logs)
--verbose               Debug-level console output
```

## Build decade playlists from the charts

`build_decade_charts.py` builds a whole decade from independent **Billboard chart**
data (not Apple's editorial "Hits" lists), so coverage is measured against the
charts — typically ~95–98% of the Year-End Hot 100, vs ~60% editorial-only.

```bash
python3 build_decade_charts.py --decade 90s            # pop, country, AC, metal, rock
python3 build_decade_charts.py --decade 90s --only pop,country,ac
python3 build_decade_charts.py --decade 80s --dry-run
```

Per genre it builds a per-year set + a master, fuzzy-matching each charting song to
Apple Music (`sync_playlist`'s matcher):

| Genre | Source |
|---|---|
| Pop | Billboard Year-End Hot 100 (Wikipedia) |
| Country | Billboard.com Year-End Hot Country Songs ∪ weekly #1s (Wikipedia) |
| Adult Contemporary | weekly AC #1s (Wikipedia) — folds into the decade master |
| Metal / Rock | Apple editorial "Essentials" (Billboard never charted these singles) — folds into the master |

Idempotent (per-playlist manifest) and crash-safe (per-batch checkpoint). AC's
year-end isn't archived online so it's #1s-depth; metal/rock have no historical
chart at all, hence Apple editorial. A guard (`era_plausible`) drops Billboard.com
year-end pages that fall back to serving the *current* chart for a missing year.

## Honest limitations

- **"Complete incl. features" is *near*-complete.** Apple has no single
  "all songs by artist" endpoint; features come from album-level views
  (`appears-on-albums`, `compilation-albums`, `featured-albums`), and those views
  are documented to occasionally return empty for some artists. So a few guest
  spots may be missed; add them by hand and they're preserved on re-runs.
- **Rate limits are unpublished.** Apple may or may not impose Spotify-style
  punitive cooldowns under heavy enumeration — unknown. The cache + throttle +
  fail-fast keep usage low; if you hit a 429, the tool stops cleanly (rc 4) and
  the cache means the next run won't re-scan. Don't hammer.
- **Catalog vs library ids.** Adding catalog song ids creates library copies with
  different ids; re-run dedupe maps them back via `playParams.catalogId`. If Apple
  ever omits that, a re-run could re-add a few tracks — verify on first update.
- **Editing playlist metadata.** The REST API can set a `description` only at
  *create* time — PATCH/PUT/DELETE on a library playlist all return **401**. To
  update an *existing* playlist's description, use **AppleScript** instead
  (`set description of user playlist …`), which works and syncs to iCloud —
  `enrich_descriptions.py` does this for every `[PL]` playlist. **Custom artwork
  can't be set by either path** (the API has no upload endpoint; AppleScript's
  playlist `artwork` is read-only) — Apple's auto-generated track mosaic is the only
  programmatic option, and custom covers must be applied by hand in Music.app.
  `generate_covers.py` makes real-imagery covers (via Pillow) to
  `~/Downloads/applemusic-complete-playlist/covers/` for that manual application:
  the artist's official Apple Music photo for `<Artist> Complete` lists, and a grid
  collage of album art from the most-represented artists for decade/genre/country/AC
  lists. To apply one: Music.app → Edit Playlist → the photo option → choose the file.

## Files

| File | Purpose |
|---|---|
| `build_playlist.py` | The artist-complete tool (self-bootstrapping venv; pure logic is import-clean for tests). |
| `build_decade.py` | Decade playlists from Apple editorial "Hits: YYYY" lists. |
| `build_decade_charts.py` | Decade playlists from Billboard charts (pop/country/AC) + editorial metal/rock. |
| `sync_playlist.py` | Variant-tolerant matcher: any `[{artist,title}]` source → Apple Music playlist. |
| `authorize.py` | One-time MusicKit-JS browser auth → saves the Music User Token. |
| `test_*.py` | Unit tests (no network/tokens) for each tool's pure logic. |
| `config.local.json.example` | Credential template (copy → `config.local.json`). |

## Tests

```bash
python3 test_build_playlist.py        # 23 — keep/drop, dedupe, planning, manifest checkpoint
python3 test_build_decade_charts.py   # 10 — chart parsers, era guard, decade math
python3 test_sync_playlist.py         # 16 — title/artist normalization + matching
```

No network or tokens needed — all suites exercise the pure logic with plain dicts
and inline HTML fixtures.
