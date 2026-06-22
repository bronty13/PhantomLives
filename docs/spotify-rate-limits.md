# Spotify Web API rate limits & Development-Mode quotas (READ BEFORE building Spotify integrations)

**This has bitten this repo twice and cost a full day of downtime each time.** It
is the single most important operational fact about talking to the Spotify Web
API from a personal app. Read this before writing or debugging any Spotify code.

Affected subprojects:

- **`MusicJournal/`** — syncs your own playlists + tracks (Swift).
- **`spotify-complete-playlist/`** — builds exhaustive per-artist playlists (Python).
- Any future Spotify integration.

## ⚠️ February 2026 Dev-Mode lockdown (READ FIRST — it explains almost everything)

Spotify shipped sweeping **Development-Mode restrictions in February 2026**
([official migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)).
These are the *documented* root cause of nearly every error this repo hit — they
are not quirks to reverse-engineer. **Read the migration guide before writing or
debugging Spotify code.** The ones that bite us:

| Dev-Mode change (Feb 2026) | Symptom we saw |
|---|---|
| **Batch fetch endpoints REMOVED** (`GET /albums`, `/tracks`, `/artists`, …) — "fetch items individually" | A 20×-fewer-calls batch optimization **does not work** in dev mode; you're forced into one call per album, which is what makes scans rate-limit-heavy |
| **`limit` max cut 50 → 10**, default 20 → 5 | `400 Invalid limit` on `artist_albums`/search with `limit>10`; pagination costs ~5× more pages |
| **`/playlists/{id}/tracks` → `/playlists/{id}/items`**; only for owned/collab playlists | Playlist responses use an `items` key, not `tracks` |
| **`/users/{id}` and `/users/{id}/playlists` restricted to `/me`** | `403` creating a playlist via `POST /users/{id}/playlists` (the create-403); must pre-create the playlist in-app |
| **User profile loses `country`, `email`, `product`, `explicit_content`** | `me()` returns `country=None`, `product=None` (NOT a missing-scope issue) |
| **Dropped fields** on tracks/albums/artists: `popularity`, `available_markets`, `external_ids`, `followers` | Don't rely on these in dev mode |
| **App rules**: owner must have **Premium**; max **1 Client ID per developer**; max **5 users/app** | Can't dodge limits by spinning up apps (also see ⛔ below) |

**Bottom line:** the Feb-2026 changes make Development Mode *hostile* to bulk
catalog work — no batch endpoints, tiny pagination, tight rate limits. **Extended
Quota Mode apps are explicitly "unaffected" by all of the above.** If you need to
do real volume, Extended Quota is not a nice-to-have, it's the prerequisite.

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

### ⛔ Do NOT spin up / delete-and-recreate an app to dodge a cooldown
It is tempting to think "a new app = a fresh quota, build today." **Don't.**
Real incident (MusicJournal, 2026): the account is effectively limited to one
app, and **deleting an app and creating another triggered a *multi-day* cooldown
on app *creation* itself** — strictly worse than waiting out the request cooldown.
A support ticket about it **was never answered**. Conclusion:
- **Waiting out the 429 cooldown is the fastest reliable path.** The `Retry-After`
  is the ETA; the on-disk cache makes the post-cooldown run cheap.
- If you ever *do* want a second app to isolate quotas (below), create it
  **proactively while not limited** — **never** delete a working app, and never
  treat app-creation as a cooldown escape hatch.

## Shared-app caveat (important)

`spotify-complete-playlist` currently **reuses MusicJournal's Spotify Developer
app** (same Client ID — its redirect list contains both `musicjournal://callback`
and `http://127.0.0.1:8888/callback`). **The quota is per *app*, so heavy use in
one tool eats the other's budget** — building big playlists here can rate-limit
MusicJournal, and vice-versa.

If this becomes a problem, you *could* give `spotify-complete-playlist` its **own**
Developer app (separate Client ID/secret in its `config.local.json`) to isolate
the quotas — **but only set it up proactively, while nothing is rate-limited, and
never by deleting the existing app** (see the ⛔ warning above: app
deletion/recreation has its own multi-day lockout, and the account is effectively
capped at one app). In practice, the cache + throttle keep usage low enough that a
single shared app is fine; prefer that over juggling apps.

## Related Development-Mode restrictions (not rate limits, same root cause)

- **Write restrictions.** A dev-mode app/account may be able to *read* and *add to
  existing* playlists but **not create new ones** (`POST /users/{id}/playlists`
  → 403). Workaround: create the empty playlist by hand in the Spotify app, then
  let the tool fill it (it's find-or-create). Extended Quota may also resolve this.
- **Other users' playlists return no tracks.** MusicJournal hides non-owned
  playlists for this reason.

### Gutted read endpoints — verified dead-end (2026-06-22 probe, applemusic-complete-playlist)

After the ~24h cooldown cleared, a careful 6-call probe of the dev-mode app
(`spotify-complete-playlist`, shared Client ID) found the *read* surface is
hollowed out — **don't re-probe these, they won't come back without action:**

- **`GET /audio-features/{id}` → 403.** The energy/valence/tempo/danceability data
  (the one thing Apple Music doesn't expose) is **permanently deprecated** for apps
  without prior extended access (Spotify's **Nov-2024 deprecation**, which also
  killed `/recommendations`, `/audio-analysis`, related-artists, and
  featured/category playlists). Waiting out a cooldown does **not** restore these.
- **`GET /artists/{id}/top-tracks` → 403.** Blocked in dev mode.
- **Artist `genres` and `popularity` come back `None`** — stripped from the objects
  the same way `/me` loses `country`/`product`. So no genre/popularity enrichment.
- **What still works:** `GET /me`, `search` (artist/track/playlist, 200 but with the
  stripped fields), and track/album `release_date`. That's it — and with **no batch
  endpoints + capped pagination**, any real audit is one-call-per-track = the
  hundreds-of-calls pattern that triggers the 24h lockout. Not worth it.

**Conclusion:** dev-mode Spotify cannot meaningfully *enrich or audit* a catalog —
the useful signals are 403/stripped and the workable reads are lock-fragile. The
Billboard-chart + Apple-Music foundation is strictly better for that work. Only
**Extended Quota Mode** (Dashboard request, server-side) reopens create/batch/
pagination/fields — but it will **not** revive the Nov-2024-deprecated endpoints.

## Quick reference

| Symptom | Meaning | Action |
|---|---|---|
| `429` + `Retry-After: <big>` | Quota exhausted | **Stop.** Wait the stated time. Don't retry. |
| Script hangs silently for ages | Client is sleeping for `Retry-After` | Use `status_retries=0` / fail-fast; kill & wait |
| `403` on playlist **create** | Dev-mode write restriction | Pre-create empty playlist in app; or Extended Quota |
| Cooldown keeps growing | Retrying into the wall | Stop all requests; let it reset |
| "I'll just make a new app" | App create/delete has its OWN multi-day cooldown; ~1 app/account | **Don't.** Wait out the 429 instead |
