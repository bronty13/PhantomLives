#!/usr/bin/env python3
"""
build_decade.py — build by-year + master "remember the past" playlists from Apple
Music's own editorial '<Genre> Hits: 19XX' and 'Essentials' lists.

For each year it merges the requested genre 'Hits: YEAR' editorial playlists into
one owned playlist (e.g. '80s — 1985 [PL]'); decade-level 'Essentials' lists (e.g.
metal, which has no per-year series) become their own playlist; and everything is
merged into a master ('80s — Complete [PL]'). Songs are Apple catalog ids copied
straight from Apple's curation — recognizable hits, no fuzzy matching.

Idempotent: re-runs append only what's new (per-playlist manifest). --dry-run
reports what it would build without writing.

Usage:
  python3 build_decade.py --decade 80s --dry-run
  python3 build_decade.py --decade 80s
"""

from __future__ import annotations

import argparse
import os
import re
import sys

import build_playlist as bp

log = bp.log

DECADES = {
    "80s": {
        "prefix": "80s — ",
        "years": list(range(1980, 1990)),
        "genre_templates": [
            "Pop Hits: {y}", "Rock Hits: {y}",
            "Alternative Hits: {y}", "Hip-Hop/R&B Hits: {y}",
        ],
        # decade-level essentials (no per-year series) -> their own playlist.
        "essentials": {
            "Metal": ["80s Metal Essentials", "80s Thrash Essentials", "80s Hard Rock Essentials"],
        },
    },
    "80s-country": {
        "prefix": "80s Country — ",
        "years": list(range(1980, 1990)),
        "genre_templates": ["Country Hits: {y}"],
        "essentials": {
            "Essentials": ["80s Country Essentials"],
        },
    },
}


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


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def find_catalog_playlist(am, sf, name: str) -> str | None:
    """Find an Apple-curated catalog playlist by (normalized) exact name."""
    r = am.get(f"/v1/catalog/{sf}/search", term=name, types="playlists", limit=10)
    items = (r.get("results", {}).get("playlists", {}) or {}).get("data", [])
    target = _norm(name)
    fallback = None
    for it in items:
        if _norm(it["attributes"].get("name", "")) == target:
            if "Apple Music" in (it["attributes"].get("curatorName", "")):
                return it["id"]
            fallback = fallback or it["id"]
    return fallback


def fetch_song_ids(am, sf, pid: str) -> list[str]:
    out = []
    for s in am.get_paginated(f"/v1/catalog/{sf}/playlists/{pid}/tracks", limit=100):
        if s.get("id"):
            out.append(s["id"])
    return out


def dedupe(ids):
    return list(dict.fromkeys(ids))


def fill_playlist(am, name: str, desired_ids: list[str], dry: bool) -> tuple[int, int]:
    """Create-or-find a library playlist and append missing ids. Returns (added, total)."""
    if dry:
        return 0, len(desired_ids)
    pid = am.find_library_playlist(name)
    if not pid:
        pid = am.create_library_playlist(name, description="80s era playlist — build_decade.py")
        existing = set()
    else:
        existing = set(am.library_playlist_catalog_ids(pid))
    existing |= bp.load_manifest(pid)
    to_add = bp.plan_additions(desired_ids, existing)
    added = am.add_catalog_songs(pid, to_add) if to_add else 0
    bp.save_manifest(pid, existing | set(to_add))
    return added, len(existing) + len(to_add)


def run(args) -> int:
    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=args.throttle)
    if not args.dry_run and not am.has_user_token:
        log.error("No Music User Token — run authorize.py first.")
        return 3
    sf = args.storefront or am.me_storefront() or cfg.get("storefront") or "us"
    spec = DECADES[args.decade]
    prefix = spec["prefix"]
    master: list[str] = []

    # Per-year, merged across genres.
    for y in spec["years"]:
        year_ids: list[str] = []
        found = []
        for tmpl in spec["genre_templates"]:
            nm = tmpl.format(y=y)
            pid = find_catalog_playlist(am, sf, nm)
            if not pid:
                log.warning("  [%d] not found: %s", y, nm)
                continue
            ids = fetch_song_ids(am, sf, pid)
            year_ids += ids
            found.append(f"{nm.split(':')[0]}={len(ids)}")
        uniq = dedupe(year_ids)
        master += uniq
        name = f"{prefix}{y} [PL]"
        added, total = fill_playlist(am, name, uniq, args.dry_run)
        log.info("%-18s %4d songs (%s)%s", name, len(uniq), ", ".join(found),
                 "" if args.dry_run else f"  → added {added}, total {total}")

    # Decade-level essentials (e.g. Metal) — their own playlist + into master.
    for label, sources in spec.get("essentials", {}).items():
        ids = []
        for src in sources:
            pid = find_catalog_playlist(am, sf, src)
            if not pid:
                log.warning("  essentials not found: %s", src)
                continue
            ids += fetch_song_ids(am, sf, pid)
        uniq = dedupe(ids)
        master += uniq
        name = f"{prefix}{label} [PL]"
        added, total = fill_playlist(am, name, uniq, args.dry_run)
        log.info("%-18s %4d songs%s", name, len(uniq),
                 "" if args.dry_run else f"  → added {added}, total {total}")

    # Master merge.
    master_uniq = dedupe(master)
    name = f"{prefix}Complete [PL]"
    added, total = fill_playlist(am, name, master_uniq, args.dry_run)
    log.info("%-18s %4d songs (merged, deduped)%s", name, len(master_uniq),
             "" if args.dry_run else f"  → added {added}, total {total}")

    log.info("RESULT: %d year playlists + essentials + master; %d unique songs total.",
             len(spec["years"]), len(master_uniq))
    if not args.dry_run:
        bp.warn_library_headroom(am)
    else:
        log.info("(--dry-run: nothing created. Re-run without --dry-run to build.)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Build by-year + master era playlists from Apple editorial lists.")
    p.add_argument("--decade", default="80s", choices=sorted(DECADES))
    p.add_argument("--storefront", default=None)
    p.add_argument("--throttle", type=float, default=0.2)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--log-dir", default=os.path.join(bp._HERE, "logs"))
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args()
    _ensure_venv()
    log_path = bp.setup_logging(args.log_dir, debug_to_console=args.verbose)
    log.info("=== build_decade '%s' start === (log: %s)", args.decade, log_path)
    try:
        rc = run(args)
    except bp.RateLimited as e:
        log.error("RATE LIMITED (429) retry-after %ss.", e.retry_after)
        return 4
    except Exception:  # noqa: BLE001
        log.exception("FATAL: build_decade failed")
        return 1
    log.info("=== build_decade end (rc=%d) ===", rc)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
