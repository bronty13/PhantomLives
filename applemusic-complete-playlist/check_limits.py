#!/usr/bin/env python3
"""
check_limits.py — keep the streaming-service limits in sight.

The binding constraint for this toolset is **Apple Music's 100,000-song LIBRARY
cap**: adding a song to a library playlist also adds it to your library, and Apple
Music's sync breaks down past 100k. This reports where you stand, warns as you
approach the cap, estimates how many more playlists fit, and appends each check to
a local history file so you can watch the trend over time.

(Spotify's relevant cap is 10,000 tracks per single playlist — every playlist we
build is far under that, and you have both services in perpetuity, so splitting is
always an option. This tool focuses on the Apple Music library, the real limit.)

Usage:
  python3 check_limits.py            # report + log a history point
  python3 check_limits.py --quiet    # one-line status (for cron/launchd)

Exit code: 0 = OK, 1 = WARN (>=85%), 2 = CRITICAL (>=95%).
"""

from __future__ import annotations

import argparse
import datetime
import os
import sys

import build_playlist as bp

log = bp.log
_HISTORY = os.path.join(bp._HERE, "limits_history.csv")


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


def _last_history():
    if not os.path.exists(_HISTORY):
        return None
    rows = [r.strip().split(",") for r in open(_HISTORY, encoding="utf-8") if r.strip()]
    data = [r for r in rows if r and r[0] != "timestamp"]
    return data[-1] if data else None


def _append_history(ts, songs, playlists):
    new = not os.path.exists(_HISTORY)
    with open(_HISTORY, "a", encoding="utf-8") as fh:
        if new:
            fh.write("timestamp,library_songs,library_playlists\n")
        fh.write(f"{ts},{songs},{playlists}\n")


def main() -> int:
    p = argparse.ArgumentParser(description="Track Apple Music / Spotify service limits.")
    p.add_argument("--quiet", action="store_true", help="One-line status only.")
    p.add_argument("--no-log", action="store_true", help="Don't append to history.")
    args = p.parse_args()
    _ensure_venv()

    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token())
    if not am.has_user_token:
        print("No Music User Token — run authorize.py first.", file=sys.stderr)
        return 1

    songs = am.library_song_total()
    playlists = (am.get("/v1/me/library/playlists", limit=1).get("meta") or {}).get("total")
    st = bp.library_status(songs)
    ts = datetime.datetime.now().isoformat(timespec="seconds")

    # Trend vs last check.
    prev = _last_history()
    delta = ""
    if prev:
        try:
            d = songs - int(prev[1])
            since = prev[0].split("T")[0]
            delta = f"  ({d:+,} since {since})"
        except (ValueError, IndexError):
            pass
    if not args.no_log:
        _append_history(ts, songs, playlists)

    icon = {"OK": "✅", "WARN": "⚠️", "CRITICAL": "🛑"}[st["level"]]
    if args.quiet:
        print(f"{icon} Apple Music library {songs:,}/{st['cap']:,} "
              f"({st['pct']*100:.1f}%){delta}")
        return {"OK": 0, "WARN": 1, "CRITICAL": 2}[st["level"]]

    bar_len = 30
    filled = int(bar_len * min(st["pct"], 1.0))
    bar = "█" * filled + "░" * (bar_len - filled)
    avg = 700  # typical "complete" artist (Flavor A) song count
    print(f"""
╭─ Streaming limits ─────────────────────────────────────────╮
  {icon}  APPLE MUSIC LIBRARY (the binding limit)
      {songs:,} / {st['cap']:,} songs   {st['pct']*100:.1f}%{delta}
      [{bar}]
      Headroom: {st['headroom']:,} songs  (~{st['headroom']//avg} more big artists,
                 or ~{st['headroom']//200} if --dedupe-by-name'd)
      Library playlists: {playlists}

  ℹ️  SPOTIFY
      Per-playlist cap 10,000 tracks — every playlist we build is well under.
      ~10,000 playlists / library total. Not a concern at this scale.

  Status: {st['level']}   (warn at 85%, critical at 95%)
  History: {os.path.basename(_HISTORY)}
╰────────────────────────────────────────────────────────────╯""")
    if st["level"] != "OK":
        print(f"  → Approaching the Apple Music cap. Options: --dedupe-by-name on "
              f"future builds, or split new artists onto Spotify.")
    return {"OK": 0, "WARN": 1, "CRITICAL": 2}[st["level"]]


if __name__ == "__main__":
    raise SystemExit(main())
