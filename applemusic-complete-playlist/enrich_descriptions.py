#!/usr/bin/env python3
"""enrich_descriptions.py — set rich descriptions on every `[PL]` playlist.

The Apple Music REST API can't update a library playlist's description (PATCH/PUT
return 401), but Music.app's AppleScript dictionary CAN, and the change syncs to
iCloud. This reads each playlist's current song count from its manifest, generates
a description (describe.py), and applies them all in one AppleScript pass.

Usage:
  python3 enrich_descriptions.py --dry-run    # print what it would set
  python3 enrich_descriptions.py              # apply via AppleScript
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

import build_playlist as bp
import describe

log = bp.log
_HERE = os.path.dirname(os.path.abspath(__file__))
_SCRIPT = os.path.join(_HERE, "set_descriptions.applescript")


def collect(am) -> list[tuple[str, int, str]]:
    """(name, count, description) for every project [PL] playlist."""
    out = []
    for pl in am.get_paginated("/v1/me/library/playlists", limit=100):
        name = pl.get("attributes", {}).get("name", "")
        if not name.endswith("[PL]"):
            continue
        count = len(bp.load_manifest(pl["id"]))
        out.append((name, count, describe.describe(name, count)))
    return out


def apply_via_applescript(rows: list[tuple[str, int, str]]) -> str:
    # one TSV: name<TAB>description (descriptions never contain tabs/newlines)
    with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False, encoding="utf-8") as fh:
        for name, _c, desc in rows:
            fh.write(f"{name}\t{desc}\n")
        tsv = fh.name
    res = subprocess.run(["osascript", _SCRIPT, tsv], capture_output=True, text=True)
    os.unlink(tsv)
    if res.returncode != 0:
        raise RuntimeError(f"osascript failed: {res.stderr.strip()}")
    return res.stdout.strip()


def main() -> int:
    p = argparse.ArgumentParser(description="Set rich descriptions on all [PL] playlists via AppleScript.")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--throttle", type=float, default=0.04)
    args = p.parse_args()

    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=args.throttle)
    rows = collect(am)
    print(f"{len(rows)} playlists.")
    if args.dry_run:
        for name, c, desc in rows[:12]:
            print(f"\n■ {name} ({c})\n   {desc}")
        print(f"\n(--dry-run: nothing applied; showed 12/{len(rows)})")
        return 0
    result = apply_via_applescript(rows)
    print(f"AppleScript applied: {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
