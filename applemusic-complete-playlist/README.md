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
updating after a new release is the same command.

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

## Files

| File | Purpose |
|---|---|
| `build_playlist.py` | The tool (self-bootstrapping venv; pure logic is import-clean for tests). |
| `authorize.py` | One-time MusicKit-JS browser auth → saves the Music User Token. |
| `test_build_playlist.py` | Unit tests for the filtering/dedupe/planning helpers. |
| `config.local.json.example` | Credential template (copy → `config.local.json`). |

## Tests

```bash
python3 test_build_playlist.py
```

16 tests covering the keep/drop rules (own vs appears-on), credit detection,
catalog-id resolution, dedupe, and add-planning — no network or tokens needed.
