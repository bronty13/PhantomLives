#!/usr/bin/env python3
"""
classical_covers.py — collect classical / instrumental cover renditions of an
artist's songs (string quartet, piano, orchestral) into one Apple Music playlist.

Approach: find dedicated *tribute albums* (e.g. 'VSQ Performs Taylor Swift',
'Taylor Swift Piano Tribute') — every track on those is a classical rendition of
the artist's songs by construction — rather than filtering individual songs.
An album qualifies when its name references the artist, it is NOT by the artist
themselves, and the artist/album name carries a classical/instrumental signal
(string quartet, piano, orchestral, classical, instrumental…).

Usage:
  python3 classical_covers.py --artist "Taylor Swift" \\
      --playlist-name "Taylor Swift — Classical Renditions [PL]" --dry-run
  (drop --dry-run to build)
"""

from __future__ import annotations

import argparse
import os
import re
import sys

import build_playlist as bp

log = bp.log

# Signals that an album is a *classical* rendition (string quartet, piano,
# orchestral). Deliberately NOT a bare "instrumental" — that also matches jazz,
# lo-fi, acoustic-guitar and karaoke "instrumental" releases, which aren't classical.
SIGNALS = ("string quartet", "quartet", "piano", "orchestr", "symphon",
           "classical", "cello", "violin", "strings", "chamber")
# Hard exclusions: a non-classical genre marker disqualifies even if "piano" appears.
EXCLUDE = ("jazz", "lo-fi", "lofi", "8-bit", "8 bit", "karaoke", "reggae",
           "metal", "steel drum", "marimba", "kalimba", "vox freaks", "guitar")

# Search angles to surface tribute albums.
QUERY_TEMPLATES = [
    "{a} string quartet", "{a} piano tribute", "{a} piano covers",
    "{a} piano renditions", "{a} classical", "{a} instrumental",
    "{a} orchestral", "Vitamin String Quartet {a}", "Midnite String Quartet {a}",
    "Piano Tribute Players {a}", "Piano Dreamers {a}", "{a} chamber",
]


def _ensure_venv() -> None:
    venv_py = bp._VENV_PY
    if os.path.abspath(sys.executable) != os.path.abspath(venv_py):
        if not os.path.exists(venv_py):
            import venv as _v
            _v.EnvBuilder(with_pip=True).create(bp._VENV)
        os.execv(venv_py, [venv_py, os.path.abspath(__file__), *sys.argv[1:]])
    try:
        import jwt, requests, cryptography  # noqa: F401
    except ImportError:
        import subprocess
        subprocess.check_call([venv_py, "-m", "pip", "install", "--quiet", "--upgrade", "pip"])
        subprocess.check_call([venv_py, "-m", "pip", "install", "--quiet", *bp._DEPS])
        os.execv(venv_py, [venv_py, os.path.abspath(__file__), *sys.argv[1:]])


def album_qualifies(artist_target: str, album_artist: str, album_name: str) -> bool:
    """An album is a classical-cover tribute to `artist_target` if it references
    the artist, is NOT by the artist, and signals classical/instrumental."""
    t = artist_target.lower()
    aa = (album_artist or "").lower()
    an = (album_name or "").lower()
    if t in aa:               # the artist's own release — skip
        return False
    if t not in an:           # album doesn't reference the artist — skip
        return False
    blob = f"{aa} {an}"
    if any(x in blob for x in EXCLUDE):   # non-classical genre marker — skip
        return False
    return any(sig in blob for sig in SIGNALS)


def run(args) -> int:
    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=args.throttle)
    sf = args.storefront or am.me_storefront() or cfg.get("storefront") or "us"
    target = args.artist

    # 1. Discover qualifying tribute albums.
    albums: dict[str, tuple[str, str]] = {}  # id -> (artist, name)
    for tmpl in QUERY_TEMPLATES:
        q = tmpl.format(a=target)
        r = am.get(f"/v1/catalog/{sf}/search", term=q, types="albums", limit=15)
        for a in (r.get("results", {}).get("albums", {}) or {}).get("data", []):
            at = a.get("attributes", {})
            if a["id"] in albums:
                continue
            if album_qualifies(target, at.get("artistName", ""), at.get("name", "")):
                albums[a["id"]] = (at.get("artistName", ""), at.get("name", ""))
    log.info("Found %d qualifying classical/instrumental tribute albums for '%s'.",
             len(albums), target)

    # 2. Fetch their tracks (all are renditions of the artist's songs).
    song_ids: list[str] = []
    per_album = []
    for aid, (aartist, aname) in albums.items():
        ids = []
        for s in am.get_paginated(f"/v1/catalog/{sf}/albums/{aid}/tracks", limit=100):
            if s.get("id") and target.lower() not in (s.get("attributes", {}).get("artistName", "")).lower():
                ids.append(s["id"])
        song_ids += ids
        per_album.append((aartist, aname, len(ids)))
        log.info("   %-26s %-44s %d trk", aartist[:26], aname[:44], len(ids))
    desired = list(dict.fromkeys(song_ids))
    log.info("Total: %d tracks across %d albums → %d unique renditions.",
             len(song_ids), len(albums), len(desired))

    if args.dry_run:
        log.info("--dry-run: nothing created.")
        return 0
    if not am.has_user_token:
        log.error("No Music User Token — run authorize.py first.")
        return 3

    name = args.playlist_name or f"{target} — Classical Renditions [PL]"
    pid = am.find_library_playlist(name)
    if not pid:
        pid = am.create_library_playlist(name, description=f"Classical/instrumental renditions of {target} — classical_covers.py")
        existing = set()
    else:
        existing = set(am.library_playlist_catalog_ids(pid))
    existing |= bp.load_manifest(pid)
    to_add = bp.plan_additions(desired, existing)
    added = am.add_catalog_songs(pid, to_add) if to_add else 0
    bp.save_manifest(pid, existing | set(to_add))
    log.info("Done. Playlist '%s': added %d (total %d).", name, added, len(existing) + len(to_add))
    bp.warn_library_headroom(am)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Build a playlist of classical/instrumental cover renditions of an artist.")
    p.add_argument("--artist", required=True)
    p.add_argument("--playlist-name", default=None)
    p.add_argument("--storefront", default=None)
    p.add_argument("--throttle", type=float, default=0.15)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--log-dir", default=os.path.join(bp._HERE, "logs"))
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args()
    _ensure_venv()
    bp.setup_logging(args.log_dir, debug_to_console=args.verbose)
    log.info("=== classical_covers '%s' start ===", args.artist)
    try:
        rc = run(args)
    except bp.RateLimited as e:
        log.error("RATE LIMITED (429) retry-after %ss.", e.retry_after)
        return 4
    except Exception:  # noqa: BLE001
        log.exception("FATAL")
        return 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
