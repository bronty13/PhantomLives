# Spotify Web API rate limits & Development-Mode quotas (READ BEFORE building Spotify integrations)

**This has bitten this repo twice and cost a full day of downtime each time.** It
is the single most important operational fact about talking to the Spotify Web
API from a personal app. Read this before writing or debugging any Spotify code.

Affected subprojects:

- **`MusicJournal/`** — syncs your own playlists + tracks (Swift).
- **`spotify-complete-playlist/`** — builds exhaustive per-artist playlists (Python).
- Any future Spotify integration.

## The core problem

A Spotify Developer app starts in **Development Mode**, which has a **tight,
undocumented request quota**. When you exceed it, the API returns **HTTP 429**
with a `Retry-After` header — and that value is **not** always "a few seconds."
When you blow past the longer-window (≈daily) quota, Spotify can hand back a
`Retry-After` of **many hours**.

> Real incident (2026-06-20, `spotify-complete-playlist`): repeated full-catalog
> scans (each ≈800 API calls) within a short window tripped a **`Retry-After` of
> 84,917 s ≈ 23.6 hours**. The app was unusable for the rest of the day.
> MusicJournal hit the same wall earlier and was down for a day.

Two traps make it worse:

1. **Client libraries may *sleep* for `Retry-After`.** spotipy, by default,
   honours `Retry-After` and will block the process for its *entire* duration —
   so a naive script silently hangs for ~24 h instead of erroring.
2. **Retrying into the wall can *extend* the cooldown.** Each additional request
   while limited can push the window out further. Do **not** keep retrying.

## Mitigations (apply all of them)

### 1. Don't re-fetch what you already have — cache aggressively
The expensive thing is *discovery* (walking a discography / all playlists). Do it
**once**, persist the result, and reuse it.
- `spotify-complete-playlist` caches the full scanned catalog to
  `cache_catalog/<artist>__<groups>__<market>.json`. Normal runs (fill / update)
  read the cache and make only ~20 calls; a re-scan happens only with
  `--refresh-catalog`.
- MusicJournal stores everything in local SQLite; sync is manual, not on every view.

### 2. Throttle requests — never burst
- MusicJournal: **1 s** between playlists, **500 ms** between paginated track pages.
- `spotify-complete-playlist`: `--throttle` (default **0.3 s**) after every
  paginated request during a scan.

### 3. Fail fast on 429 — never sleep for `Retry-After`
- `spotify-complete-playlist` constructs the client with `status_retries=0` so a
  429 raises immediately instead of sleeping for hours; the top-level handler
  prints the cooldown in hours and exits (rc 4).
- MusicJournal throws `SpotifyError.rateLimited(retryAfter:)`, skips the playlist,
  and surfaces the value to the user.

### 4. When limited, STOP. Wait it out.
The `Retry-After` value *is* the ETA. Waiting is the only reliable cure for a
Development-Mode cooldown. Resume after it elapses; thanks to the cache, the next
run is cheap.

### 5. The permanent fix: Extended Quota Mode
In the Spotify Developer Dashboard, submit a **Quota Extension request** for the
app. Approval lifts Development-Mode restrictions (higher limits; also removes the
"can only read playlists you own" / restricted-write behaviour). **No code change
— the limits are server-side.** For light personal use it's usually unnecessary;
the cache + throttle keep you under the dev quota. Request it if you genuinely
need higher throughput or write access the dev tier denies.

## Shared-app caveat (important)

`spotify-complete-playlist` currently **reuses MusicJournal's Spotify Developer
app** (same Client ID — its redirect list contains both `musicjournal://callback`
and `http://127.0.0.1:8888/callback`). **The quota is per *app*, so heavy use in
one tool eats the other's budget** — building big playlists here can rate-limit
MusicJournal, and vice-versa.

If this becomes a problem, give `spotify-complete-playlist` its **own** Developer
app (separate Client ID/secret in its `config.local.json`) to isolate the quotas.
The trade-off is a second one-time OAuth setup.

## Related Development-Mode restrictions (not rate limits, same root cause)

- **Write restrictions.** A dev-mode app/account may be able to *read* and *add to
  existing* playlists but **not create new ones** (`POST /users/{id}/playlists`
  → 403). Workaround: create the empty playlist by hand in the Spotify app, then
  let the tool fill it (it's find-or-create). Extended Quota may also resolve this.
- **Other users' playlists return no tracks.** MusicJournal hides non-owned
  playlists for this reason.

## Quick reference

| Symptom | Meaning | Action |
|---|---|---|
| `429` + `Retry-After: <big>` | Quota exhausted | **Stop.** Wait the stated time. Don't retry. |
| Script hangs silently for ages | Client is sleeping for `Retry-After` | Use `status_retries=0` / fail-fast; kill & wait |
| `403` on playlist **create** | Dev-mode write restriction | Pre-create empty playlist in app; or Extended Quota |
| Cooldown keeps growing | Retrying into the wall | Stop all requests; let it reset |
