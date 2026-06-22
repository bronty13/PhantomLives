#!/usr/bin/env python3
"""generate_covers.py — REAL-IMAGERY cover art for every `[PL]` playlist.

Apple won't let custom playlist artwork be set via API or AppleScript, so these are
generated to a folder for manual application in Music.app (Edit Playlist → photo
option → choose file). Two styles, pulled from the Apple Music catalog:

  * Artist `Complete` playlists  -> the artist's official Apple Music photo.
  * Decade / genre / country / AC -> a grid collage of album covers from the
    playlist's most-represented artists (one album per artist, deduped).

Album/artist art comes from Apple's public mzstatic CDN (the `artwork.url` template
on catalog resources). Downloaded tiles are cached under cover_cache/. Requires
Pillow. Falls back to a plain gradient if no art is available.

Usage:
  python3 generate_covers.py --only "80s — Complete [PL]","Metallica Complete [PL]"
  python3 generate_covers.py            # all [PL] playlists
"""
from __future__ import annotations

import argparse
import hashlib
import io
import os
import re
from collections import Counter

import build_playlist as bp

from PIL import Image

log = bp.log
SIZE = 1200
OUT = os.path.expanduser("~/Downloads/applemusic-complete-playlist/covers")
_CACHE = os.path.join(bp._HERE, "cover_cache")


def art_url(template: str, size: int) -> str:
    return (template or "").replace("{w}", str(size)).replace("{h}", str(size))


def fetch_image(template: str, size: int):
    """Download (cached) an mzstatic artwork URL -> square RGB PIL image, or None."""
    if not template:
        return None
    key = hashlib.md5((template + f"|{size}").encode()).hexdigest() + ".jpg"
    path = os.path.join(_CACHE, key)
    if os.path.exists(path):
        try:
            return Image.open(path).convert("RGB")
        except Exception:
            pass
    import requests
    try:
        r = requests.get(art_url(template, size), timeout=30)
        if r.status_code != 200:
            return None
        img = Image.open(io.BytesIO(r.content)).convert("RGB")
    except Exception:
        return None
    os.makedirs(_CACHE, exist_ok=True)
    try:
        img.save(path, "JPEG", quality=90)
    except Exception:
        pass
    return img


def square(img, s):
    """Center-crop to square and resize to s."""
    w, h = img.size
    m = min(w, h)
    img = img.crop(((w - m) // 2, (h - m) // 2, (w - m) // 2 + m, (h - m) // 2 + m))
    return img.resize((s, s))


# --- gradient fallback (kept from the text-art version, used only when no art) ---
def _grad(c0, c1):
    col = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        col.putpixel((0, y), tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)))
    return col.resize((SIZE, SIZE))


def collage(images, accent=(20, 20, 24)):
    """Square grid collage from a list of square PIL images (best-fit NxN)."""
    images = [im for im in images if im is not None]
    if not images:
        return _grad((40, 40, 50), (10, 10, 14))
    import math
    n = len(images)
    grid = max(2, min(4, int(round(math.sqrt(n)))))
    need = grid * grid
    tiles = (images * ((need // n) + 1))[:need]      # repeat to fill if short
    cell = SIZE // grid
    canvas = Image.new("RGB", (SIZE, SIZE), accent)
    for i, im in enumerate(tiles):
        x, y = (i % grid) * cell, (i // grid) * cell
        canvas.paste(square(im, cell), (x, y))
    return canvas


# --- classification ---
def is_artist_complete(name: str):
    if name.endswith("— Classical Renditions [PL]"):
        return re.sub(r"\s*—\s*Classical Renditions \[PL\]$", "", name)
    if re.match(r"^(70s|80s|90s|2000s|2010s)", name):
        return None
    if name in ("Life in Music [PL]", "Brent Mason — Played On [PL]", "Metal — Complete [PL]"):
        return None
    m = re.match(r"^(.+?) Complete \[PL\]$", name)
    if m and not m.group(1).lower().endswith(("metal", "metalcore", "deathcore")):
        return m.group(1)
    return None


def artist_photo(am, sf, artist_name):
    try:
        aid, _ = am.resolve_artist(sf, artist_name)
        r = am.get(f"/v1/catalog/{sf}/artists/{aid}")
        tmpl = (r["data"][0]["attributes"].get("artwork") or {}).get("url")
        img = fetch_image(tmpl, SIZE)
        return square(img, SIZE) if img else None
    except Exception:
        return None


def top_artist_albums(am, sf, pid, n=16):
    """Album covers for the playlist's most-represented artists (one per artist)."""
    ids = sorted(bp.load_manifest(pid))
    if not ids:
        return []
    by_artist = {}          # artistName -> artwork template (first seen)
    freq = Counter()
    for chunk in bp.chunked(ids, 300):
        r = am.get(f"/v1/catalog/{sf}/songs", ids=",".join(chunk))
        for d in r.get("data", []):
            a = d.get("attributes", {})
            an = a.get("artistName", "")
            freq[an] += 1
            if an and an not in by_artist:
                by_artist[an] = (a.get("artwork") or {}).get("url")
    top = [a for a, _ in freq.most_common() if by_artist.get(a)][:n]
    return [fetch_image(by_artist[a], SIZE // 4) for a in top]


def render(am, sf, name, count):
    artist = is_artist_complete(name)
    if artist:
        img = artist_photo(am, sf, artist)
        if img:
            return img, "artist-photo"
    pid = am.find_library_playlist(name)
    if pid:
        tiles = top_artist_albums(am, sf, pid)
        if tiles:
            return collage(tiles), "collage"
    return _grad((50, 30, 70), (10, 10, 20)), "fallback"


def safe(name):
    # JPEG: photographic covers (artist photos / album collages) compress ~10x
    # smaller than PNG, and Apple Music accepts JPEG for custom artwork.
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")[:120] + ".jpg"


def main():
    p = argparse.ArgumentParser(description="Generate real-imagery covers for [PL] playlists.")
    p.add_argument("--only", default=None, help="comma list of exact playlist names")
    p.add_argument("--throttle", type=float, default=0.05)
    args = p.parse_args()
    os.makedirs(OUT, exist_ok=True)
    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=args.throttle)
    sf = am.me_storefront() or cfg.get("storefront") or "us"

    if args.only:
        names = [s.strip() for s in args.only.split(",")]
        rows = [(nm, len(bp.load_manifest(am.find_library_playlist(nm) or ""))) for nm in names]
    else:
        rows = [(pl["attributes"]["name"], len(bp.load_manifest(pl["id"])))
                for pl in am.get_paginated("/v1/me/library/playlists", limit=100)
                if pl.get("attributes", {}).get("name", "").endswith("[PL]")]

    done = Counter()
    for nm, count in rows:
        try:                                  # one transient 500 shouldn't kill the run
            img, kind = render(am, sf, nm, count)
            img.save(os.path.join(OUT, safe(nm)), "JPEG", quality=88)
            done[kind] += 1
        except Exception as e:                # noqa: BLE001
            done["error"] += 1
            log.warning("  %-44s ERROR %s", nm[:44], str(e)[:60])
    print(f"Wrote {sum(v for k,v in done.items() if k!='error')} covers to {OUT}  ({dict(done)})")


if __name__ == "__main__":
    raise SystemExit(main())
