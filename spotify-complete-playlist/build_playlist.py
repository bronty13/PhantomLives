#!/usr/bin/env python3
"""
build_playlist.py — Build a *complete* Spotify playlist of one artist's catalog.

Unlike Spotify's in-app "AI playlist" generator (which caps results, ~60 tracks),
this talks to the real Spotify Web API and adds the *exact* tracks you want:
every album, single, compilation, AND every track where the artist merely
appears as a featured guest/collaborator ("appears_on"). Deduped by track URI
so re-recordings ("Taylor's Version") and vault tracks are kept, not collapsed.

It is idempotent: on every run it reads what's already in the target playlist and
adds only what's missing. That makes "update it on occasion" a one-liner — just
run it again and any newly-released songs get appended.

Defaults are tuned for the original ask: artist "Taylor Swift", playlist
"Taylor Swift Complete". Override with flags to build the same kind of
exhaustive playlist for any artist.

Setup (one-time) and full usage notes live in README.md.

This file self-bootstraps a local .venv and installs `spotipy` on first run.
The pure data-shaping helpers at the top import no third-party packages, so the
test suite can import this module without spotipy or network access.
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

# Module logger. Configured by setup_logging() in main(); functions just call
# log.info()/log.warning() etc. Logging (vs print) gives us a flushed-per-record
# file handler, so a background run can be tailed in realtime regardless of how
# stdout is buffered through a pipe.
log = logging.getLogger("build_playlist")

# --------------------------------------------------------------------------- #
#  Pure helpers (no spotipy, no network) — safe to import in tests
# --------------------------------------------------------------------------- #

# Spotify album "groups" we pull. "appears_on" is what captures songs where the
# artist is only a featured/guest collaborator on someone else's release.
DEFAULT_INCLUDE_GROUPS = ("album", "single", "compilation", "appears_on")

# Groups that are the artist's *own* releases — every track on these is kept.
OWN_GROUPS = frozenset({"album", "single", "compilation"})

# Max page size the live /artists/{id}/albums endpoint accepts. Spotify's docs
# say 50, but as of 2026-06 the API rejects anything >10 with "Invalid limit"
# (verified empirically). Pagination still fetches everything; it just takes more
# round-trips. Other endpoints (album_tracks, playlist_items) are unaffected.
ALBUMS_PAGE_LIMIT = 10


def track_is_by_artist(track: dict, artist_id: str) -> bool:
    """True if `artist_id` is credited anywhere on the track."""
    return any(a.get("id") == artist_id for a in track.get("artists", []))


def track_is_primary_artist(track: dict, artist_id: str) -> bool:
    """True if `artist_id` is the FIRST credited artist on the track."""
    artists = track.get("artists", [])
    return bool(artists) and artists[0].get("id") == artist_id


def keep_track(track: dict, artist_id: str, album_group: str) -> bool:
    """
    Decide whether a track belongs in the complete playlist.

    - On the artist's own releases (album/single/compilation): keep every track
      (collab songs on her own albums credit her as primary anyway).
    - On "appears_on" releases: keep only tracks where she is actually credited
      AND is not the primary artist — i.e. genuine features/guest spots. This
      avoids re-pulling her own songs that happen to sit on third-party
      compilations.
    """
    if track.get("is_local"):
        return False
    if not track.get("uri"):
        return False
    if album_group in OWN_GROUPS:
        return True  # own release: keep every track (incl. vault/deluxe/collabs)
    # appears_on
    return track_is_by_artist(track, artist_id) and not track_is_primary_artist(
        track, artist_id
    )


def dedupe_by_uri(tracks: Iterable[dict]) -> list[dict]:
    """
    Collapse exact duplicate recordings (same URI appearing on, say, a single
    and its parent album) while PRESERVING distinct recordings that share a
    title — re-records and remixes have different URIs, so they survive.
    First occurrence wins (stable order).
    """
    seen: set[str] = set()
    out: list[dict] = []
    for t in tracks:
        uri = t.get("uri")
        if not uri or uri in seen:
            continue
        seen.add(uri)
        out.append(t)
    return out


def dedupe_by_name(tracks: Iterable[dict]) -> list[dict]:
    """
    Collapse tracks that share an identical title, keeping the first occurrence.
    Because group order is own-releases-first, the artist's own version of a song
    wins over a guest/compilation copy. Crucially this dedupes by the FULL title,
    so distinct versions whose titles differ — "(Taylor's Version)",
    "(From The Vault)", "- Live", "- Acoustic Version", remixes — are preserved;
    only true title-collisions (the same song re-released on deluxe/anniversary
    editions) are merged. Use when you want one entry per distinct song rather
    than every available recording/edition.
    """
    seen: set[str] = set()
    out: list[dict] = []
    for t in tracks:
        key = (t.get("name") or "").strip().casefold()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(t)
    return out


def catalog_cache_key(artist_id: str, include_groups: Iterable[str], market: str) -> str:
    """Stable filename for a cached catalog scan, keyed by artist + groups + market."""
    groups = "-".join(include_groups)
    return f"{artist_id}__{groups}__{market}.json"


def plan_additions(desired_uris: list[str], existing_uris: Iterable[str]) -> list[str]:
    """
    Given the full desired set and what's already in the playlist, return the
    URIs to add (missing ones only), de-duplicated and in desired order.
    This is what makes re-runs incremental.
    """
    existing = set(existing_uris)
    to_add: list[str] = []
    added: set[str] = set()
    for uri in desired_uris:
        if uri in existing or uri in added:
            continue
        added.add(uri)
        to_add.append(uri)
    return to_add


def chunked(seq: list, size: int) -> Iterable[list]:
    """Yield `size`-length chunks (Spotify add/remove caps at 100 per call)."""
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


# --------------------------------------------------------------------------- #
#  venv bootstrap
# --------------------------------------------------------------------------- #

_HERE = os.path.dirname(os.path.abspath(__file__))
_VENV = os.path.join(_HERE, ".venv")
_VENV_PY = os.path.join(_VENV, "bin", "python")


def _ensure_venv_and_deps() -> None:
    """
    Re-exec inside a local .venv with spotipy installed. Idempotent: once we're
    running the venv's python and spotipy imports, this is a no-op.
    """
    in_venv = os.path.abspath(sys.executable) == os.path.abspath(_VENV_PY)

    if not in_venv:
        if not os.path.exists(_VENV_PY):
            print("Creating virtual environment (.venv)…", file=sys.stderr)
            import venv

            venv.EnvBuilder(with_pip=True).create(_VENV)
        os.execv(_VENV_PY, [_VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])

    # We are now inside the venv.
    try:
        import spotipy  # noqa: F401
    except ImportError:
        print("Installing dependencies (spotipy)…", file=sys.stderr)
        subprocess.check_call(
            [_VENV_PY, "-m", "pip", "install", "--quiet", "--upgrade", "pip"]
        )
        subprocess.check_call(
            [_VENV_PY, "-m", "pip", "install", "--quiet", "spotipy>=2.24.0"]
        )
        os.execv(_VENV_PY, [_VENV_PY, os.path.abspath(__file__), *sys.argv[1:]])


# --------------------------------------------------------------------------- #
#  Credentials
# --------------------------------------------------------------------------- #

_CONFIG_FILE = os.path.join(_HERE, "config.local.json")


def _load_credentials() -> None:
    """
    Populate SPOTIPY_* env vars (which spotipy reads natively) from, in order:
    existing env vars, then config.local.json if present. Does not overwrite
    env vars that are already set.
    """
    if os.path.exists(_CONFIG_FILE):
        with open(_CONFIG_FILE) as fh:
            cfg = json.load(fh)
        mapping = {
            "client_id": "SPOTIPY_CLIENT_ID",
            "client_secret": "SPOTIPY_CLIENT_SECRET",
            "redirect_uri": "SPOTIPY_REDIRECT_URI",
        }
        for key, env in mapping.items():
            if cfg.get(key) and not os.environ.get(env):
                os.environ[env] = str(cfg[key])

    os.environ.setdefault("SPOTIPY_REDIRECT_URI", "http://127.0.0.1:8888/callback")

    missing = [
        env
        for env in ("SPOTIPY_CLIENT_ID", "SPOTIPY_CLIENT_SECRET")
        if not os.environ.get(env)
    ]
    if missing:
        sys.exit(
            "ERROR: missing Spotify credentials: "
            + ", ".join(missing)
            + ".\nSet them as environment variables or in config.local.json "
            "(see README.md → Setup)."
        )


# --------------------------------------------------------------------------- #
#  Spotify API wrappers (spotipy imported lazily)
# --------------------------------------------------------------------------- #


class PlaylistCreateForbidden(Exception):
    """Raised when the Spotify app/account may read & modify-existing playlists
    but is not allowed to CREATE one (HTTP 403 on POST /users/{id}/playlists)."""


class RateLimited(Exception):
    """Raised on HTTP 429. `retry_after` is seconds Spotify asks us to wait."""

    def __init__(self, retry_after: int | None):
        self.retry_after = retry_after
        super().__init__(f"rate limited; retry after {retry_after}s")


_CACHE_DIR = os.path.join(_HERE, "cache_catalog")


def setup_logging(log_dir: str, debug_to_console: bool = False) -> str:
    """
    Send logs to BOTH a timestamped file (full detail, flushed per record so it
    can be tailed live) and the console. Returns the log file path.
    """
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


def _client(open_browser: bool = True):
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth

    # modify: to add tracks / create the playlist; read-private: to find an
    # existing playlist by name (GET /me/playlists) so re-runs are idempotent.
    scope = "playlist-modify-public playlist-modify-private playlist-read-private"
    auth = SpotifyOAuth(
        scope=scope,
        cache_path=os.path.join(_HERE, ".cache"),
        open_browser=open_browser,
    )
    # status_retries=0: do NOT auto-retry on 429. Spotify can send a Retry-After
    # of many hours when an app exceeds its (Development-Mode) quota, and spotipy
    # would otherwise SLEEP for that whole duration. We'd rather fail fast and
    # surface the cooldown. retries=2 still covers transient network blips.
    return spotipy.Spotify(
        auth_manager=auth, requests_timeout=30, retries=2, status_retries=0
    )


def resolve_artist(sp, name: str, artist_id: str | None) -> tuple[str, str]:
    if artist_id:
        info = sp.artist(artist_id)
        return info["id"], info["name"]
    res = sp.search(q=name, type="artist", limit=5)
    items = res.get("artists", {}).get("items", [])
    if not items:
        sys.exit(f"ERROR: no artist found for '{name}'.")
    # Prefer an exact (case-insensitive) name match, else the top hit.
    for it in items:
        if it["name"].lower() == name.lower():
            return it["id"], it["name"]
    return items[0]["id"], items[0]["name"]


def fetch_all_albums(sp, artist_id, include_groups, market, throttle: float = 0.0):
    """Yield (album_dict, group) for every album, paginating fully."""
    for group in include_groups:
        offset = 0
        while True:
            page = sp.artist_albums(
                artist_id,
                include_groups=group,
                limit=ALBUMS_PAGE_LIMIT,
                offset=offset,
                country=market,
            )
            if throttle:
                time.sleep(throttle)
            items = page.get("items", [])
            for alb in items:
                yield alb, group
            if len(items) < ALBUMS_PAGE_LIMIT:
                break
            offset += ALBUMS_PAGE_LIMIT


def fetch_album_tracks(sp, album_id: str, market: str, throttle: float = 0.0) -> list[dict]:
    tracks: list[dict] = []
    offset = 0
    while True:
        page = sp.album_tracks(album_id, limit=50, offset=offset, market=market)
        if throttle:
            time.sleep(throttle)
        items = page.get("items", [])
        tracks.extend(items)
        if len(items) < 50:
            break
        offset += 50
    return tracks


def existing_playlist_uris(sp, playlist_id: str) -> list[str]:
    uris: list[str] = []
    offset = 0
    while True:
        page = sp.playlist_items(
            playlist_id,
            limit=100,
            offset=offset,
            fields="items(track(uri)),next",
            additional_types=("track",),
        )
        items = page.get("items", [])
        for it in items:
            tr = it.get("track") or {}
            if tr.get("uri"):
                uris.append(tr["uri"])
        if not page.get("next"):
            break
        offset += 100
    return uris


def find_playlist(sp, user_id: str, name: str) -> str | None:
    """Return the id of a playlist OWNED by the user with this exact name, else None."""
    offset = 0
    while True:
        page = sp.current_user_playlists(limit=50, offset=offset)
        for pl in page.get("items", []):
            if pl["name"] == name and pl["owner"]["id"] == user_id:
                return pl["id"]
        if not page.get("next"):
            break
        offset += 50
    return None


def create_playlist(sp, user_id: str, name: str, public: bool) -> str:
    import spotipy

    try:
        created = sp.user_playlist_create(
            user_id,
            name,
            public=public,
            description="Complete catalog incl. features — built by build_playlist.py",
        )
    except spotipy.SpotifyException as e:
        if e.http_status == 403:
            raise PlaylistCreateForbidden(name) from e
        raise
    return created["id"]


# --------------------------------------------------------------------------- #
#  Main
# --------------------------------------------------------------------------- #


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Build a complete Spotify playlist of an artist's catalog "
        "(incl. features), via the Spotify Web API."
    )
    p.add_argument("--artist", default="Taylor Swift", help="Artist name to search.")
    p.add_argument("--artist-id", default=None, help="Exact Spotify artist ID (skips search).")
    p.add_argument(
        "--playlist-name", default="Taylor Swift Complete", help="Target playlist name."
    )
    p.add_argument("--market", default=None, help="Market/country code (default: your account's).")
    p.add_argument(
        "--include-groups",
        default=",".join(DEFAULT_INCLUDE_GROUPS),
        help="Comma-separated album groups (album,single,compilation,appears_on).",
    )
    p.add_argument(
        "--no-features",
        action="store_true",
        help="Skip 'appears_on' — only the artist's own releases.",
    )
    p.add_argument(
        "--dedupe-by-name",
        action="store_true",
        help="Collapse same-title recordings to one entry per distinct song "
        "(keeps Taylor's Version / vault / live / remix, since their titles differ).",
    )
    p.add_argument("--public", action="store_true", help="Make a new playlist public (default private).")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute and report, but don't modify the playlist.",
    )
    p.add_argument(
        "--log-dir",
        default=os.path.join(_HERE, "logs"),
        help="Directory for timestamped run logs (default: ./logs).",
    )
    p.add_argument(
        "--no-browser",
        action="store_true",
        help="Never open a browser for auth (headless/unattended). Fails clearly "
        "if the cached token is missing/expired instead of hanging.",
    )
    p.add_argument(
        "--refresh-catalog",
        action="store_true",
        help="Force a fresh Spotify scan instead of using the on-disk catalog "
        "cache (use when the artist has new releases). Rate-limit-heavy.",
    )
    p.add_argument(
        "--throttle",
        type=float,
        default=0.3,
        help="Seconds to pause after each paginated API request during a scan, "
        "to stay under Spotify's dev-mode rate limit (default: 0.3).",
    )
    p.add_argument("--verbose", action="store_true", help="Debug-level console output.")
    return p.parse_args(argv)


def add_tracks(sp, playlist_id: str, to_add: list[str]) -> int:
    """
    Add tracks in batches of 100. A failing batch is retried item-by-item so one
    bad/unavailable URI can't abort the whole run — each skip is logged. Returns
    the number actually added.
    """
    added = 0
    batches = list(chunked(to_add, 100))
    for i, batch in enumerate(batches, 1):
        try:
            sp.playlist_add_items(playlist_id, batch)
            added += len(batch)
            log.info("  batch %d/%d: +%d  (%d/%d added)",
                     i, len(batches), len(batch), added, len(to_add))
        except Exception as e:  # noqa: BLE001 — isolate the offending URI(s)
            log.warning("  batch %d/%d failed (%d tracks): %s — retrying individually",
                        i, len(batches), len(batch), e)
            for uri in batch:
                try:
                    sp.playlist_add_items(playlist_id, [uri])
                    added += 1
                except Exception as e2:  # noqa: BLE001
                    log.warning("    skipped %s: %s", uri, e2)
    return added


def scan_catalog(sp, artist_id, include_groups, market, throttle: float = 0.0) -> list[dict]:
    """
    Walk the artist's whole discography and return URI-deduped track dicts
    [{"uri","name"}]. This is the EXPENSIVE step (hundreds of API calls), so its
    result is cached to disk by load_or_build_catalog(). `throttle` adds a delay
    after each paginated request to stay under Spotify's dev-mode rate limit.
    """
    collected: list[dict] = []
    seen_albums: set[str] = set()
    album_count = 0
    for alb, group in fetch_all_albums(sp, artist_id, include_groups, market, throttle):
        if alb["id"] in seen_albums:
            continue
        seen_albums.add(alb["id"])
        album_count += 1
        for tr in fetch_album_tracks(sp, alb["id"], market, throttle):
            if keep_track(tr, artist_id, group):
                collected.append({"uri": tr["uri"], "name": tr.get("name")})
        if album_count % 25 == 0:
            log.info("  …scanned %d albums, %d candidate tracks", album_count, len(collected))
    deduped = dedupe_by_uri(collected)
    log.info("Scanned %d albums → %d candidate tracks → %d unique recordings.",
             album_count, len(collected), len(deduped))
    return deduped


def load_or_build_catalog(sp, args, artist_id, artist_name, include_groups, market):
    """
    Return the URI-deduped catalog [{"uri","name"}], from the on-disk cache when
    available (and not --refresh-catalog), else by scanning and then saving it.
    Caching means the costly full scan happens once; fills/updates reuse it and
    stay well under Spotify's rate limit.
    """
    cache_path = os.path.join(
        _CACHE_DIR, catalog_cache_key(artist_id, include_groups, market)
    )
    if not args.refresh_catalog and os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as fh:
            data = json.load(fh)
        tracks = data.get("tracks", [])
        log.info("Loaded catalog from cache: %d recordings (built %s)",
                 len(tracks), data.get("generated_at", "?"))
        log.info("  (%s — pass --refresh-catalog to re-scan)", cache_path)
        return tracks

    log.info("Scanning catalog from Spotify (this is the rate-limit-heavy step; "
             "throttle=%.2fs/request)…", args.throttle)
    tracks = scan_catalog(sp, artist_id, include_groups, market, args.throttle)
    os.makedirs(_CACHE_DIR, exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as fh:
        json.dump(
            {
                "generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
                "artist_id": artist_id,
                "artist_name": artist_name,
                "market": market,
                "groups": list(include_groups),
                "tracks": tracks,
            },
            fh,
            ensure_ascii=False,
            indent=0,
        )
    log.info("Saved catalog cache: %s", cache_path)
    return tracks


def run(args: argparse.Namespace) -> int:
    _load_credentials()
    sp = _client(open_browser=not args.no_browser)

    me = sp.me()
    user_id = me["id"]
    market = args.market or me.get("country") or "US"

    include_groups = tuple(g.strip() for g in args.include_groups.split(",") if g.strip())
    if args.no_features:
        include_groups = tuple(g for g in include_groups if g != "appears_on")

    artist_id, artist_name = resolve_artist(sp, args.artist, args.artist_id)
    log.info("Artist: %s (%s)", artist_name, artist_id)
    log.info("Market: %s   Groups: %s", market, ", ".join(include_groups))

    catalog = load_or_build_catalog(
        sp, args, artist_id, artist_name, include_groups, market
    )
    uniq_recordings = len(catalog)
    if args.dedupe_by_name:
        catalog = dedupe_by_name(catalog)
        log.info("After per-song dedupe: %d distinct songs (by title)", len(catalog))
    desired_uris = [t["uri"] for t in catalog]

    playlist_id = find_playlist(sp, user_id, args.playlist_name)

    if args.dry_run:
        existing = existing_playlist_uris(sp, playlist_id) if playlist_id else []
        to_add = plan_additions(desired_uris, existing)
        where = f"found existing ({playlist_id})" if playlist_id else "would be created"
        log.info("Playlist '%s': %s", args.playlist_name, where)
        log.info("Already in playlist: %d   Would add: %d", len(existing), len(to_add))
        log.info("--dry-run: no changes made.")
        return 0

    if playlist_id:
        log.info("Playlist '%s': found existing (%s)", args.playlist_name, playlist_id)
        existing = existing_playlist_uris(sp, playlist_id)
    else:
        try:
            playlist_id = create_playlist(sp, user_id, args.playlist_name, args.public)
        except PlaylistCreateForbidden:
            log.error(
                "Spotify refused to CREATE a playlist (HTTP 403) — this app/account "
                "can read and add to existing playlists but not create new ones."
            )
            log.error("FIX: in the Spotify app, create an EMPTY playlist named exactly:")
            log.error("        %s", args.playlist_name)
            log.error("then re-run this command. It will find that playlist and fill it.")
            return 3
        log.info("Playlist '%s': created (%s)", args.playlist_name, playlist_id)
        existing = []

    to_add = plan_additions(desired_uris, existing)
    log.info("Already in playlist: %d   To add: %d", len(existing), len(to_add))

    added = add_tracks(sp, playlist_id, to_add)
    log.info("Done. Added %d tracks. Playlist now has ~%d tracks.",
             added, len(existing) + added)
    log.info("Open: https://open.spotify.com/playlist/%s", playlist_id)
    return 0


def _as_rate_limit(exc) -> RateLimited | None:
    """If exc is a spotipy 429, return a RateLimited carrying its Retry-After."""
    try:
        import spotipy
    except ImportError:
        return None
    if isinstance(exc, spotipy.SpotifyException) and exc.http_status == 429:
        retry = None
        headers = getattr(exc, "headers", None) or {}
        for k, v in headers.items():
            if k.lower() == "retry-after":
                try:
                    retry = int(v)
                except (TypeError, ValueError):
                    retry = None
        return RateLimited(retry)
    return None


def main() -> int:
    args = parse_args()
    _ensure_venv_and_deps()
    log_path = setup_logging(args.log_dir, debug_to_console=args.verbose)
    log.info("=== build_playlist start === (log: %s)", log_path)
    try:
        rc = run(args)
    except Exception as exc:  # noqa: BLE001 — top-level: log a clear cause
        rl = _as_rate_limit(exc)
        if rl is not None:
            secs = rl.retry_after
            human = f"~{secs / 3600:.1f} h" if secs else "unknown duration"
            log.error("RATE LIMITED by Spotify (HTTP 429). Cooldown: %s (%s s).",
                      human, secs if secs else "?")
            log.error("This app's request quota is exhausted — do NOT keep retrying;")
            log.error("each retry can extend the cooldown. Wait it out, then re-run.")
            log.error("The catalog cache means the next run won't re-scan. See README "
                      "→ 'Spotify rate limits'.")
            return 4
        log.exception("FATAL: build failed")
        return 1
    log.info("=== build_playlist end (rc=%d) ===", rc)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
