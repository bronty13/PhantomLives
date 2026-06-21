#!/usr/bin/env python3
"""
build_playlist.py — Build a *complete* Apple Music playlist of one artist's catalog.

Companion to ../spotify-complete-playlist, rebuilt on the Apple Music API after
Spotify's February-2026 Development-Mode lockdown made bulk catalog work on
Spotify untenable (removed batch endpoints, pagination capped at 10, restricted
user endpoints; see ../docs/spotify-rate-limits.md).

What it does: enumerates an artist's whole catalog from Apple Music — their own
albums/singles PLUS albums where they only appear as a featured/secondary artist
("appears-on") — expands every album to its songs, filters the appears-on songs
to those that actually credit the artist, dedupes by catalog song id, then
creates (or idempotently appends to) a library playlist.

AUTH (two tokens — see README.md):
  • Developer Token  — an ES256 JWT you sign with a MusicKit private key (.p8)
    from your Apple Developer account. Needed for ALL requests. Catalog reads
    need ONLY this token, so the whole enumeration half can be verified before
    dealing with the user token.
  • Music User Token — minted ONCE via the interactive MusicKit-JS page
    (`authorize.py`), then reused. Needed only for /v1/me/library writes
    (create playlist / add tracks).

Rate-limit hygiene from day one (Apple does not publish quotas — treat as
unknown): throttle every request, cache the catalog scan, fail fast on HTTP 429
(never sleep for hours), log everything to a tailable file.

The pure data-shaping helpers at the top import no third-party packages, so the
test suite imports this module without requests/PyJWT or any network.
"""

from __future__ import annotations

import argparse
import datetime
import json
import logging
import os
import subprocess
import sys
import time
from typing import Iterable

log = logging.getLogger("applemusic_build")

# --------------------------------------------------------------------------- #
#  Pure helpers (no third-party imports, no network) — safe to import in tests
# --------------------------------------------------------------------------- #

# Catalog artist relationship/views we pull. "albums" is the artist's own
# releases (albums, EPs, singles). The view names surface secondary appearances.
OWN_ALBUMS_RELATIONSHIP = "albums"
APPEARS_ON_VIEWS = ("appears-on-albums", "compilation-albums", "featured-albums")


def song_artist_ids(song: dict) -> list[str]:
    """Catalog artist ids credited on a song, from its included `artists` rel."""
    rels = song.get("relationships") or {}
    arts = (rels.get("artists") or {}).get("data") or []
    return [a.get("id") for a in arts if a.get("id")]


def song_credits_artist(song: dict, artist_id: str) -> bool:
    """True if the artist is credited on the song (needs include=artists)."""
    return artist_id in song_artist_ids(song)


def keep_song(song: dict, artist_id: str, is_appears_on: bool) -> bool:
    """
    Decide whether a song belongs in the complete playlist.

    - On the artist's OWN releases: keep every track.
    - On an APPEARS-ON album (a compilation / someone else's release): keep only
      tracks that actually credit the artist — otherwise a compilation would drag
      in dozens of unrelated songs. This requires the song's `artists`
      relationship to have been included in the request.
    """
    if not song.get("id"):
        return False
    if not is_appears_on:
        return True
    return song_credits_artist(song, artist_id)


def song_play_catalog_id(song: dict) -> str | None:
    """
    Best-effort catalog id for a song resource. For catalog songs this is just
    `id`. For LIBRARY songs (read back from a playlist) the real catalog id lives
    in attributes.playParams.catalogId — used to dedupe re-runs against catalog
    ids. Returns None if neither is present.
    """
    attrs = song.get("attributes") or {}
    pp = attrs.get("playParams") or {}
    cat = pp.get("catalogId") or pp.get("purchasedId")
    if cat:
        return cat
    # Library song with the catalog relationship included (read with include=catalog):
    rels = song.get("relationships") or {}
    cdata = (rels.get("catalog") or {}).get("data") or []
    if cdata and cdata[0].get("id"):
        return cdata[0]["id"]
    # A catalog song resource: its own id IS the catalog id.
    if song.get("type") == "songs" and song.get("id"):
        return song["id"]
    return None


def dedupe_by_id(items: Iterable[dict], key: str = "id") -> list[dict]:
    """Stable de-dupe by a key (first occurrence wins)."""
    seen: set[str] = set()
    out: list[dict] = []
    for it in items:
        k = it.get(key)
        if not k or k in seen:
            continue
        seen.add(k)
        out.append(it)
    return out


def plan_additions(desired_ids: list[str], existing_ids: Iterable[str]) -> list[str]:
    """Catalog ids to add: desired minus already-present, de-duped, in order."""
    existing = set(existing_ids)
    out: list[str] = []
    added: set[str] = set()
    for cid in desired_ids:
        if cid in existing or cid in added:
            continue
        added.add(cid)
        out.append(cid)
    return out


def chunked(seq: list, size: int) -> Iterable[list]:
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def catalog_cache_key(artist_id: str, storefront: str) -> str:
    return f"{storefront}__{artist_id}.json"


# --------------------------------------------------------------------------- #
#  venv bootstrap
# --------------------------------------------------------------------------- #

_HERE = os.path.dirname(os.path.abspath(__file__))
_VENV = os.path.join(_HERE, ".venv")
_VENV_PY = os.path.join(_VENV, "bin", "python")
_DEPS = ("requests>=2.31", "PyJWT>=2.8", "cryptography>=42.0")


def _ensure_venv_and_deps() -> None:
    """Re-exec inside a local .venv with requests + PyJWT + cryptography."""
    in_venv = os.path.abspath(sys.executable) == os.path.abspath(_VENV_PY)
    if not in_venv:
        if not os.path.exists(_VENV_PY):
            print("Creating virtual environment (.venv)…", file=sys.stderr)
            import venv

            venv.EnvBuilder(with_pip=True).create(_VENV)
        os.execv(_VENV_PY, [_VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])
    try:
        import jwt  # noqa: F401
        import requests  # noqa: F401
        import cryptography  # noqa: F401
    except ImportError:
        print("Installing dependencies (requests, PyJWT, cryptography)…", file=sys.stderr)
        subprocess.check_call([_VENV_PY, "-m", "pip", "install", "--quiet", "--upgrade", "pip"])
        subprocess.check_call([_VENV_PY, "-m", "pip", "install", "--quiet", *_DEPS])
        os.execv(_VENV_PY, [_VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])


# --------------------------------------------------------------------------- #
#  Config, tokens, logging
# --------------------------------------------------------------------------- #

_CONFIG_FILE = os.path.join(_HERE, "config.local.json")
_USER_TOKEN_FILE = os.path.join(_HERE, "music_user_token.json")
_CACHE_DIR = os.path.join(_HERE, "cache_catalog")

API_BASE = "https://api.music.apple.com"
# Developer token lifetime: 180 days (Apple max is 15777000s ≈ 6 months).
DEV_TOKEN_TTL = 180 * 24 * 3600


class RateLimited(Exception):
    def __init__(self, retry_after: int | None):
        self.retry_after = retry_after
        super().__init__(f"rate limited; retry after {retry_after}s")


class NeedsUserToken(Exception):
    """Raised when a library write is attempted without a Music User Token."""


def setup_logging(log_dir: str, debug_to_console: bool = False) -> str:
    os.makedirs(log_dir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = os.path.join(log_dir, f"build_{stamp}.log")
    log.setLevel(logging.DEBUG)
    log.handlers.clear()
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%H:%M:%S")
    fh = logging.FileHandler(log_path, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    log.addHandler(fh)
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.DEBUG if debug_to_console else logging.INFO)
    ch.setFormatter(fmt)
    log.addHandler(ch)
    return log_path


def load_config() -> dict:
    if not os.path.exists(_CONFIG_FILE):
        sys.exit(
            "ERROR: config.local.json not found. Copy config.local.json.example "
            "and fill in team_id, key_id, and private_key_path (see README.md)."
        )
    with open(_CONFIG_FILE, encoding="utf-8") as fh:
        cfg = json.load(fh)
    for req in ("team_id", "key_id", "private_key_path"):
        if not cfg.get(req):
            sys.exit(f"ERROR: config.local.json is missing '{req}' (see README.md).")
    return cfg


def sign_developer_token(cfg: dict, ttl: int = DEV_TOKEN_TTL) -> str:
    """Sign an ES256 JWT developer token from the MusicKit .p8 private key."""
    import jwt  # PyJWT (lazy import; not needed for unit tests)

    p8_path = os.path.expanduser(cfg["private_key_path"])
    if not os.path.exists(p8_path):
        sys.exit(f"ERROR: private key not found at {p8_path} (see README.md).")
    with open(p8_path, encoding="utf-8") as fh:
        private_key = fh.read()
    now = int(time.time())
    if ttl > 15777000:  # Apple's hard max (6 months)
        ttl = 15777000
    payload = {"iss": cfg["team_id"], "iat": now, "exp": now + ttl}
    return jwt.encode(
        payload, private_key, algorithm="ES256", headers={"alg": "ES256", "kid": cfg["key_id"]}
    )


def load_user_token() -> str | None:
    if not os.path.exists(_USER_TOKEN_FILE):
        return None
    with open(_USER_TOKEN_FILE, encoding="utf-8") as fh:
        return (json.load(fh) or {}).get("music_user_token") or None


# --------------------------------------------------------------------------- #
#  Apple Music REST client (requests imported lazily)
# --------------------------------------------------------------------------- #


class AppleMusic:
    def __init__(self, dev_token: str, user_token: str | None, throttle: float = 0.2):
        import requests

        self._requests = requests
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {dev_token}"
        if user_token:
            self.session.headers["Music-User-Token"] = user_token
        self.has_user_token = bool(user_token)
        self.throttle = throttle

    # -- low-level ---------------------------------------------------------- #
    def _request(self, method: str, path: str, *, params=None, json_body=None):
        url = path if path.startswith("http") else f"{API_BASE}{path}"
        resp = self.session.request(method, url, params=params, json=json_body, timeout=30)
        if self.throttle:
            time.sleep(self.throttle)
        if resp.status_code == 429:
            ra = resp.headers.get("Retry-After")
            raise RateLimited(int(ra) if ra and ra.isdigit() else None)
        if not resp.ok:
            raise RuntimeError(
                f"{method} {url} -> HTTP {resp.status_code}: {resp.text[:300]}"
            )
        return resp.json() if resp.content else {}

    def get(self, path, **params):
        return self._request("GET", path, params=params or None)

    def post(self, path, json_body):
        return self._request("POST", path, json_body=json_body)

    def get_paginated(self, path, **params):
        """Yield every `data` item across all `next` pages."""
        page = self.get(path, **params)
        while True:
            for item in page.get("data", []):
                yield item
            nxt = page.get("next")
            if not nxt:
                break
            # `next` is a relative path that already encodes offset; it does NOT
            # carry our query params, so re-send the ones that matter (limit/include).
            page = self.get(nxt, **{k: v for k, v in params.items() if k in ("limit", "include")})

    # -- high-level --------------------------------------------------------- #
    def me_storefront(self) -> str | None:
        if not self.has_user_token:
            return None
        data = self.get("/v1/me/storefront").get("data", [])
        return data[0]["id"] if data else None

    def resolve_artist(self, storefront: str, name: str) -> tuple[str, str]:
        res = self.get(
            f"/v1/catalog/{storefront}/search", term=name, types="artists", limit=5
        )
        items = (res.get("results", {}).get("artists", {}) or {}).get("data", [])
        if not items:
            sys.exit(f"ERROR: no Apple Music artist found for '{name}'.")
        for it in items:
            if (it.get("attributes", {}).get("name", "")).lower() == name.lower():
                return it["id"], it["attributes"]["name"]
        return items[0]["id"], items[0]["attributes"]["name"]

    def artist_album_ids(self, storefront: str, artist_id: str) -> dict[str, bool]:
        """
        Map album_id -> is_appears_on. Own releases come from the `albums`
        relationship (is_appears_on=False); secondary appearances from the
        appears-on/compilation/featured VIEWS (is_appears_on=True). Own wins on
        overlap.
        """
        result: dict[str, bool] = {}
        base = f"/v1/catalog/{storefront}/artists/{artist_id}"
        # Own releases.
        for alb in self.get_paginated(f"{base}/{OWN_ALBUMS_RELATIONSHIP}", limit=100):
            if alb.get("id"):
                result[alb["id"]] = False
        log.info("  own albums: %d", len(result))
        # Secondary appearances (views).
        for view in APPEARS_ON_VIEWS:
            count = 0
            try:
                for alb in self.get_paginated(f"{base}/view/{view}", limit=100):
                    aid = alb.get("id")
                    if aid and aid not in result:  # own takes precedence
                        result[aid] = True
                        count += 1
            except RuntimeError as e:
                log.warning("  view %s unavailable (%s) — skipping", view, str(e)[:80])
            log.info("  view %s: +%d albums", view, count)
        return result

    def album_songs(self, storefront: str, album_id: str, need_artists: bool):
        """Yield song resources for an album; include=artists when filtering features."""
        params = {"limit": 100}
        if need_artists:
            params["include"] = "artists"
        yield from self.get_paginated(
            f"/v1/catalog/{storefront}/albums/{album_id}/tracks", **params
        )

    # -- library writes (need user token) ----------------------------------- #
    def find_library_playlist(self, name: str) -> str | None:
        if not self.has_user_token:
            raise NeedsUserToken()
        for pl in self.get_paginated("/v1/me/library/playlists", limit=100):
            if (pl.get("attributes", {}).get("name")) == name:
                return pl["id"]
        return None

    def create_library_playlist(self, name: str, description: str | None = None) -> str:
        if not self.has_user_token:
            raise NeedsUserToken()
        attrs: dict = {"name": name}
        if description:
            attrs["description"] = description
        resp = self.post("/v1/me/library/playlists", {"attributes": attrs})
        return resp["data"][0]["id"]

    def library_playlist_catalog_ids(self, playlist_id: str) -> list[str]:
        """Catalog ids already in the library playlist (for idempotent re-runs)."""
        if not self.has_user_token:
            raise NeedsUserToken()
        out: list[str] = []
        for song in self.get_paginated(
            f"/v1/me/library/playlists/{playlist_id}/tracks", limit=100, include="catalog"
        ):
            cid = song_play_catalog_id(song)
            if cid:
                out.append(cid)
        return out

    def add_catalog_songs(self, playlist_id: str, catalog_song_ids: list[str]) -> int:
        """Append catalog songs to a library playlist (batches of 100)."""
        if not self.has_user_token:
            raise NeedsUserToken()
        added = 0
        batches = list(chunked(catalog_song_ids, 100))
        for i, batch in enumerate(batches, 1):
            body = {"data": [{"id": cid, "type": "songs"} for cid in batch]}
            self.post(f"/v1/me/library/playlists/{playlist_id}/tracks", body)
            added += len(batch)
            log.info("  batch %d/%d: +%d (%d/%d)", i, len(batches), len(batch),
                     added, len(catalog_song_ids))
        return added


# --------------------------------------------------------------------------- #
#  Catalog scan (+ disk cache)
# --------------------------------------------------------------------------- #


def scan_catalog(am: AppleMusic, storefront: str, artist_id: str, throttle: float) -> list[dict]:
    """
    Walk the artist's discography and return URI-deduped song dicts
    [{"id","name"}]. Expensive (one request per album + pagination), so cached.
    """
    album_map = am.artist_album_ids(storefront, artist_id)
    log.info("  enumerated %d albums (%d own, %d appears-on); expanding to songs…",
             len(album_map),
             sum(1 for v in album_map.values() if not v),
             sum(1 for v in album_map.values() if v))
    collected: list[dict] = []
    done = 0
    for album_id, is_appears_on in album_map.items():
        for song in am.album_songs(storefront, album_id, need_artists=is_appears_on):
            if keep_song(song, artist_id, is_appears_on):
                collected.append({"id": song["id"], "name": (song.get("attributes") or {}).get("name")})
        done += 1
        if done % 25 == 0 or done == len(album_map):
            log.info("  …expanded %d/%d albums, %d candidate songs", done, len(album_map), len(collected))
    deduped = dedupe_by_id(collected)
    log.info("Scanned %d albums → %d candidate songs → %d unique recordings.",
             len(album_map), len(collected), len(deduped))
    return deduped


_STATE_DIR = os.path.join(_HERE, "playlist_state")


def load_manifest(playlist_id: str) -> set[str]:
    """Catalog ids we've previously added to this playlist (local source of truth).

    Apple's library loses the catalog id for ~40% of added songs, so reading the
    playlist back can't reliably tell us what's already there — this local record
    can. Keyed by the stable Apple library playlist id.
    """
    p = os.path.join(_STATE_DIR, f"{playlist_id}.json")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as fh:
            return set((json.load(fh) or {}).get("added", []))
    return set()


def save_manifest(playlist_id: str, ids: Iterable[str]) -> None:
    os.makedirs(_STATE_DIR, exist_ok=True)
    with open(os.path.join(_STATE_DIR, f"{playlist_id}.json"), "w", encoding="utf-8") as fh:
        json.dump({"added": sorted(set(ids))}, fh)


def load_or_build_catalog(am, args, storefront, artist_id, artist_name) -> list[dict]:
    os.makedirs(_CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(_CACHE_DIR, catalog_cache_key(artist_id, storefront))
    if not args.refresh_catalog and os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as fh:
            data = json.load(fh)
        songs = data.get("songs", [])
        log.info("Loaded catalog from cache: %d recordings (built %s); --refresh-catalog to re-scan",
                 len(songs), data.get("generated_at", "?"))
        return songs
    log.info("Scanning catalog from Apple Music (rate-limit-heavy; throttle=%.2fs)…", args.throttle)
    songs = scan_catalog(am, storefront, artist_id, args.throttle)
    with open(cache_path, "w", encoding="utf-8") as fh:
        json.dump({"generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
                   "storefront": storefront, "artist_id": artist_id,
                   "artist_name": artist_name, "songs": songs}, fh, ensure_ascii=False)
    log.info("Saved catalog cache: %s", cache_path)
    return songs


# --------------------------------------------------------------------------- #
#  CLI
# --------------------------------------------------------------------------- #


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Build a complete Apple Music playlist of an artist's catalog "
        "(incl. features) via the Apple Music API."
    )
    p.add_argument("--artist", default=None, help="Artist name to search.")
    p.add_argument("--artist-id", default=None, help="Exact Apple Music catalog artist id.")
    p.add_argument("--playlist-name", default=None, help="Target library playlist name.")
    p.add_argument("--storefront", default=None, help="Storefront/country code (default: your account's, else 'us').")
    p.add_argument("--throttle", type=float, default=0.2, help="Seconds to pause after each API request (default 0.2).")
    p.add_argument("--refresh-catalog", action="store_true", help="Force a fresh scan instead of the cached catalog.")
    p.add_argument("--dry-run", action="store_true", help="Scan + report, but don't create/modify the playlist.")
    p.add_argument("--verify-token", action="store_true",
                   help="Just verify the developer token with a catalog read (no user token needed) and exit.")
    p.add_argument("--log-dir", default=os.path.join(_HERE, "logs"), help="Run-log directory (default ./logs).")
    p.add_argument("--verbose", action="store_true", help="Debug-level console output.")
    return p.parse_args(argv)


def run(args) -> int:
    cfg = load_config()
    dev_token = sign_developer_token(cfg)
    user_token = load_user_token()
    am = AppleMusic(dev_token, user_token, throttle=args.throttle)

    # --verify-token: prove the developer token works (catalog read only).
    if args.verify_token:
        sf = args.storefront or cfg.get("storefront") or "us"
        res = am.get(f"/v1/catalog/{sf}/search", term="Taylor Swift", types="artists", limit=1)
        items = (res.get("results", {}).get("artists", {}) or {}).get("data", [])
        if items:
            log.info("Developer token OK ✓ — catalog read returned: %s (%s)",
                     items[0]["attributes"]["name"], items[0]["id"])
            return 0
        log.error("Developer token signed but catalog read returned no data.")
        return 1

    if not args.artist and not args.artist_id:
        sys.exit("ERROR: provide --artist NAME (or --artist-id). Use --verify-token to just test auth.")
    if not args.playlist_name:
        sys.exit("ERROR: provide --playlist-name.")

    storefront = args.storefront or am.me_storefront() or cfg.get("storefront") or "us"
    if args.artist_id:
        info = am.get(f"/v1/catalog/{storefront}/artists/{args.artist_id}")
        artist_id = args.artist_id
        artist_name = info["data"][0]["attributes"]["name"]
    else:
        artist_id, artist_name = am.resolve_artist(storefront, args.artist)
    log.info("Artist: %s (%s)   Storefront: %s", artist_name, artist_id, storefront)

    catalog = load_or_build_catalog(am, args, storefront, artist_id, artist_name)
    desired_ids = [s["id"] for s in catalog]

    if not am.has_user_token:
        log.error("No Music User Token — catalog scan done & cached, but creating/filling the "
                  "playlist needs it. Run:  python3 authorize.py   then re-run this command.")
        return 3

    playlist_id = am.find_library_playlist(args.playlist_name)
    if args.dry_run:
        existing = am.library_playlist_catalog_ids(playlist_id) if playlist_id else []
        to_add = plan_additions(desired_ids, existing)
        log.info("Playlist '%s': %s", args.playlist_name,
                 f"found ({playlist_id})" if playlist_id else "would be created")
        log.info("Already in playlist: %d   Would add: %d", len(existing), len(to_add))
        log.info("--dry-run: no changes made.")
        return 0

    if playlist_id:
        log.info("Playlist '%s': found existing (%s)", args.playlist_name, playlist_id)
        api_existing = set(am.library_playlist_catalog_ids(playlist_id))
    else:
        playlist_id = am.create_library_playlist(
            args.playlist_name, description="Complete catalog incl. features — build_playlist.py")
        log.info("Playlist '%s': created (%s)", args.playlist_name, playlist_id)
        api_existing = set()

    # Use the local manifest as the reliable "already added" record (Apple's
    # library loses catalog ids), unioned with whatever the API can confirm.
    manifest = load_manifest(playlist_id)
    existing = manifest | api_existing
    to_add = plan_additions(desired_ids, existing)
    log.info("Already in playlist: %d (manifest %d, api %d)   To add: %d",
             len(existing), len(manifest), len(api_existing), len(to_add))
    added = am.add_catalog_songs(playlist_id, to_add)
    save_manifest(playlist_id, existing | set(to_add))
    log.info("Done. Added %d songs. Manifest now tracks %d catalog ids.",
             added, len(existing) + len(to_add))
    return 0


def main() -> int:
    args = parse_args()
    _ensure_venv_and_deps()
    log_path = setup_logging(args.log_dir, debug_to_console=args.verbose)
    log.info("=== applemusic build_playlist start === (log: %s)", log_path)
    try:
        rc = run(args)
    except RateLimited as e:
        secs = e.retry_after
        human = f"~{secs/3600:.1f} h" if secs else "unknown"
        log.error("RATE LIMITED by Apple Music (HTTP 429). Retry-After: %s (%ss).",
                  human, secs if secs else "?")
        log.error("Apple does not publish quotas — do NOT hammer. Wait, then re-run "
                  "(the catalog cache means the next run won't re-scan).")
        return 4
    except NeedsUserToken:
        log.error("A library write needs a Music User Token. Run: python3 authorize.py")
        return 3
    except Exception:  # noqa: BLE001
        log.exception("FATAL: build failed")
        return 1
    log.info("=== applemusic build_playlist end (rc=%d) ===", rc)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
