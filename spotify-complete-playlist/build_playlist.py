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
import json
import os
import subprocess
import sys
from typing import Iterable

# --------------------------------------------------------------------------- #
#  Pure helpers (no spotipy, no network) — safe to import in tests
# --------------------------------------------------------------------------- #

# Spotify album "groups" we pull. "appears_on" is what captures songs where the
# artist is only a featured/guest collaborator on someone else's release.
DEFAULT_INCLUDE_GROUPS = ("album", "single", "compilation", "appears_on")

# Groups that are the artist's *own* releases — every track on these is kept.
OWN_GROUPS = frozenset({"album", "single", "compilation"})


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


def _client():
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth

    scope = "playlist-modify-public playlist-modify-private"
    auth = SpotifyOAuth(
        scope=scope,
        cache_path=os.path.join(_HERE, ".cache"),
        open_browser=True,
    )
    return spotipy.Spotify(auth_manager=auth, requests_timeout=30, retries=5)


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


def fetch_all_albums(sp, artist_id: str, include_groups: tuple[str, ...], market: str):
    """Yield (album_dict, group) for every album, paginating fully."""
    for group in include_groups:
        offset = 0
        while True:
            page = sp.artist_albums(
                artist_id, include_groups=group, limit=50, offset=offset, country=market
            )
            items = page.get("items", [])
            for alb in items:
                yield alb, group
            if len(items) < 50:
                break
            offset += 50


def fetch_album_tracks(sp, album_id: str, market: str) -> list[dict]:
    tracks: list[dict] = []
    offset = 0
    while True:
        page = sp.album_tracks(album_id, limit=50, offset=offset, market=market)
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


def find_or_create_playlist(sp, user_id: str, name: str, public: bool):
    """Find a playlist OWNED by the user with this exact name, else create one."""
    offset = 0
    while True:
        page = sp.current_user_playlists(limit=50, offset=offset)
        for pl in page.get("items", []):
            if pl["name"] == name and pl["owner"]["id"] == user_id:
                return pl["id"], False
        if not page.get("next"):
            break
        offset += 50
    created = sp.user_playlist_create(
        user_id,
        name,
        public=public,
        description="Complete catalog incl. features — built by build_playlist.py",
    )
    return created["id"], True


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
    p.add_argument("--public", action="store_true", help="Make a new playlist public (default private).")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute and report, but don't modify the playlist.",
    )
    return p.parse_args(argv)


def run(args: argparse.Namespace) -> int:
    _load_credentials()
    sp = _client()

    me = sp.me()
    user_id = me["id"]
    market = args.market or me.get("country") or "US"

    include_groups = tuple(g.strip() for g in args.include_groups.split(",") if g.strip())
    if args.no_features:
        include_groups = tuple(g for g in include_groups if g != "appears_on")

    artist_id, artist_name = resolve_artist(sp, args.artist, args.artist_id)
    print(f"Artist: {artist_name} ({artist_id})")
    print(f"Market: {market}   Groups: {', '.join(include_groups)}")

    # Gather candidate tracks across all album groups.
    collected: list[dict] = []
    seen_albums: set[str] = set()
    album_count = 0
    for alb, group in fetch_all_albums(sp, artist_id, include_groups, market):
        if alb["id"] in seen_albums:
            continue
        seen_albums.add(alb["id"])
        album_count += 1
        for tr in fetch_album_tracks(sp, alb["id"], market):
            if keep_track(tr, artist_id, group):
                collected.append(tr)
        if album_count % 25 == 0:
            print(f"  …scanned {album_count} albums, {len(collected)} candidate tracks")

    deduped = dedupe_by_uri(collected)
    desired_uris = [t["uri"] for t in deduped]
    print(
        f"Scanned {album_count} albums → {len(collected)} candidate tracks "
        f"→ {len(desired_uris)} unique recordings."
    )

    playlist_id, created = find_or_create_playlist(
        sp, user_id, args.playlist_name, args.public
    )
    print(f"Playlist '{args.playlist_name}': {'created' if created else 'found existing'} ({playlist_id})")

    existing = [] if created else existing_playlist_uris(sp, playlist_id)
    to_add = plan_additions(desired_uris, existing)
    print(f"Already in playlist: {len(existing)}   To add: {len(to_add)}")

    if args.dry_run:
        print("--dry-run: no changes made.")
        return 0

    for batch in chunked(to_add, 100):
        sp.playlist_add_items(playlist_id, batch)
    print(f"Done. Added {len(to_add)} tracks. Playlist now has "
          f"{len(existing) + len(to_add)} tracks.")
    print(f"Open: https://open.spotify.com/playlist/{playlist_id}")
    return 0


def main() -> int:
    args = parse_args()
    _ensure_venv_and_deps()
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
