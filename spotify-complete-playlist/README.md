# spotify-complete-playlist

Build a **complete** Spotify playlist of one artist's entire catalog — every
album, single, compilation, **and** every track where the artist only appears as
a featured guest/collaborator — by talking to the real **Spotify Web API**.

This exists because Spotify's in-app "AI playlist" generator (and the chat
connector that wraps it) **caps results at ~60 tracks** and curates rather than
enumerates. This tool instead adds the *exact* tracks, deduped by recording, so
you get the whole discography — re-recordings ("Taylor's Version"), vault
tracks, deluxe editions, and features included.

Defaults are tuned for the original use case: artist **Taylor Swift**, playlist
**Taylor Swift Complete**. Point it at any artist with flags.

## Why this and not the in-app generator?

| | In-app / chat "AI playlist" | This tool (Web API) |
|---|---|---|
| Track count | Capped (~60) | Every available recording |
| Control | AI-curated | Exact tracks you specify |
| Features ("appears_on") | Hit or miss | Explicitly included |
| Re-records / vault tracks | Often collapsed by title | Kept (deduped by URI, not name) |
| Update later | Re-generate (shuffles) | Re-run → appends only new songs |

## One-time setup (~3 minutes)

You need a free **Spotify Developer app** to get API credentials. Your normal
Spotify account is fine — no separate signup, no paid developer tier.

1. Go to <https://developer.spotify.com/dashboard> and log in with your Spotify
   account.
2. **Create app**. Name/description can be anything (e.g. "My Playlist Builder").
3. For **Redirect URI**, add exactly:

   ```
   http://127.0.0.1:8888/callback
   ```

   > ⚠️ Spotify requires a **loopback IP** (`127.0.0.1`), *not* `localhost`, for
   > new apps. Use the line above verbatim. The port (8888) is arbitrary but
   > must match what you configure here and in `redirect_uri`.

4. Save. Open the app's **Settings** and copy the **Client ID** and
   **Client Secret**.
5. Tell the tool your credentials, either way:

   - **Config file (easiest):** copy the example and paste your values:

     ```bash
     cp config.local.json.example config.local.json
     # then edit config.local.json
     ```

     (`config.local.json` is git-ignored — your secret never gets committed.)

   - **Or environment variables:**

     ```bash
     export SPOTIPY_CLIENT_ID=xxxx
     export SPOTIPY_CLIENT_SECRET=yyyy
     export SPOTIPY_REDIRECT_URI=http://127.0.0.1:8888/callback
     ```

## Run it

```bash
python3 build_playlist.py
```

On **first run** it will:

1. Create a local `.venv` and install `spotipy` (self-bootstrapping — no manual
   `pip`).
2. Open your browser to authorize the app (Spotify login → "Agree"). It then
   catches the redirect on `127.0.0.1:8888` and caches a token in `.cache`, so
   later runs don't re-prompt.
3. Scan the artist's full discography, dedupe, find-or-create the playlist, and
   add every missing track.

Example output:

```
Artist: Taylor Swift (06HL4z0CvFAxyc27GXpf02)
Market: US   Groups: album, single, compilation, appears_on
  …scanned 25 albums, 528 candidate tracks
Scanned 266 albums → 836 candidate tracks → 836 unique recordings.
Playlist 'Taylor Swift Complete': created (xxxxxxxx)
Already in playlist: 0   To add: 836
Done. Added 836 tracks. Playlist now has 836 tracks.
Open: https://open.spotify.com/playlist/xxxxxxxx
```

## Updating "on occasion"

Just run it again:

```bash
python3 build_playlist.py
```

It reads what's already in the playlist and **adds only what's new** (idempotent).
Re-running after Taylor drops a new album appends just those tracks — nothing is
duplicated or reshuffled.

## Options

```
--artist NAME           Artist to search for (default: "Taylor Swift")
--artist-id ID          Exact Spotify artist ID (skips the name search)
--playlist-name NAME    Target playlist (default: "Taylor Swift Complete")
--market CC             Market/country code (default: your account's country)
--include-groups LIST   Album groups (default: album,single,compilation,appears_on)
--no-features           Only the artist's own releases (drop "appears_on")
--dedupe-by-name        One entry per distinct song instead of every edition
                        (keeps Taylor's Version / vault / live / remix — their
                        titles differ — but collapses standard/deluxe/anniversary
                        re-releases of the same song)
--public                Make a newly-created playlist public (default: private)
--dry-run               Compute & report counts, but don't modify the playlist
```

### Choosing how "complete" you want it

Spotify assigns a **distinct track ID to the same song on every edition**
(standard / deluxe / anniversary / "3am" / target-exclusive…), so the default
"every available recording" run is large — for Taylor it lands around **800+**.
That's literally every recording, but it means several copies of, say, "Shake It
Off". Two honest flavors:

```bash
# Every available recording / edition (default) — ~800+ for Taylor
python3 build_playlist.py --dry-run

# One entry per distinct song, but re-records & vault tracks kept — much closer
# to a fan's "complete songs" count
python3 build_playlist.py --dry-run --dedupe-by-name
```

Run both with `--dry-run` first, pick the count you like, then run for real
(drop `--dry-run`).

Build a different artist's complete playlist:

```bash
python3 build_playlist.py --artist "Phoebe Bridgers" --playlist-name "Phoebe Complete"
```

Preview the count without touching anything:

```bash
python3 build_playlist.py --dry-run
```

## How "complete" is decided

- **The artist's own releases** (`album`, `single`, `compilation`): every track
  is kept.
- **`appears_on`** (someone else's release): a track is kept only if the artist
  is actually credited **and is not the primary artist** — i.e. a genuine
  feature/guest spot. This catches real collabs (e.g. *"Renegade" — Big Red
  Machine ft. Taylor Swift*) while avoiding re-pulling her own songs that happen
  to sit on third-party compilations.
- **Dedupe is by track URI**, not by title — so distinct recordings that share a
  name (original vs. *(Taylor's Version)*, single vs. album master, remixes) are
  all preserved.

### Caveats / honest limits

- The exact count depends on Spotify's catalog **in your market** at run time; it
  drifts as Spotify adds/removes releases. The default run is "every recording"
  (~800+ for Taylor); `--dedupe-by-name` gives "every distinct song". Neither is
  a fixed guarantee — it tracks Spotify's live catalog.
- `appears_on` is only as complete as Spotify's own crediting. A guest spot that
  Spotify doesn't credit to the artist won't be found automatically; add those by
  hand in the app and they'll be preserved on future runs.
- Removing tracks is intentionally **not** automated — the tool only adds, so a
  song you add manually is never wiped by a re-run.

## Files

| File | Purpose |
|---|---|
| `build_playlist.py` | The tool (self-bootstrapping venv; pure logic is import-clean for tests). |
| `test_build_playlist.py` | Unit tests for the filtering/dedupe/planning helpers (`python3 test_build_playlist.py`). |
| `config.local.json.example` | Template for your credentials (copy → `config.local.json`). |

## Tests

```bash
python3 test_build_playlist.py
```

13 tests covering credit detection, the keep/drop rules, URI dedupe (incl.
re-record preservation), and incremental add-planning. They use plain dicts and
need neither `spotipy` nor network access.
