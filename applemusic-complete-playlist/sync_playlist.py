#!/usr/bin/env python3
"""
sync_playlist.py — precisely sync a Spotify playlist's tracks into Apple Music.

Built for the "Life in Music" legacy diary: every song matched, nothing dropped
silently. Source tracks come from MusicJournal's local SQLite (so no Spotify API
needed), and each is matched to the Apple Music catalog with a VARIANT-TOLERANT
algorithm — a live/remix/remaster source matches the standard version, and when
several versions exist the cleanest (non-live/demo/remix) is preferred.

Everything is reviewable: it writes a Markdown report of every match and every
miss with a confidence tier, and caches the matches so --create reuses them.

Usage:
  python3 sync_playlist.py --playlist "Life in Music"             # match + report
  python3 sync_playlist.py --playlist "Life in Music" --create \\
      --dest "Life in Music [PL]"                                 # also build it
  python3 sync_playlist.py --source life_in_music_source.json     # from a JSON dump

Reuses build_playlist.py for the Apple Music client, playlist create/append, and
the local manifest (idempotent re-runs).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys

import build_playlist as bp

log = bp.log

# --------------------------------------------------------------------------- #
#  Pure matching helpers (no network) — unit-tested
# --------------------------------------------------------------------------- #

# Markers that indicate a non-standard recording. Used only as a TIE-BREAKER:
# among equally-good title matches we prefer the version with the fewest of these
# (i.e. the plain studio version over a live/demo/remix), since the source is a
# memory of a song, and the standard recording is the most faithful stand-in.
_VARIANT_MARKERS = (
    "live", "demo", "remix", "karaoke", "instrumental", "commentary",
    "acoustic", "session", "edit", "mix", "rerecorded", "re recorded",
    "sped up", "slowed", "cover", "tribute", "made famous", "in the style",
)


def norm_title(t: str) -> str:
    """Core title for matching: drop ' - <suffix>', (…)/[…], 'feat …', punctuation."""
    t = (t or "").lower()
    t = re.sub(r"\s+-\s+.*$", "", t)  # drop " - <suffix>" (spaces required: keeps "Ob-La-Di")
    t = re.sub(r"[\(\[].*?[\)\]]", "", t)
    # "feat"/"ft" must be followed by whitespace — else "Feather"/"ft." inside a
    # word would be wrongly truncated (it ate the whole title "Feather" -> "").
    t = re.sub(r"\bfeat\.?\s+.*$", "", t)
    t = re.sub(r"\bft\.?\s+.*$", "", t)
    return re.sub(r"[^a-z0-9]+", " ", t).strip()


def _censored_match(src_title: str, cand_title: str) -> bool:
    """True if a censored candidate (e.g. 'F**k You') is the source song, treating
    '*' as a single-char wildcard. Lets asterisk-masked titles match the source."""
    if "*" not in (cand_title or ""):
        return False

    def core(x):
        x = (x or "").lower()
        x = re.sub(r"\s+-\s+.*$", "", x)
        x = re.sub(r"[\(\[].*?[\)\]]", "", x)
        return x.strip()

    s, c = core(src_title), core(cand_title)
    pat = "".join("." if ch == "*" else (r"\s+" if ch == " " else re.escape(ch)) for ch in c)
    try:
        return re.fullmatch(pat, s) is not None
    except re.error:
        return False


def norm_artist(a: str) -> str:
    """Primary artist, normalized (first of a comma list, no 'the', no punctuation)."""
    a = (a or "").split(",")[0].split("&")[0].lower()
    a = re.sub(r"[^a-z0-9]+", " ", a).strip()
    return re.sub(r"^the\s+", "", a).strip()


def match_score(src_artist: str, src_title: str, cand_artist: str, cand_title: str) -> int:
    """
    0 = no match. Otherwise artist*10 + title where each is 2 (exact, normalized)
    or 1 (containment). So 22 = exact artist + exact title (best); 11 = both only
    contained. A score of 0 if either artist or title doesn't relate at all.
    """
    sa, st = norm_artist(src_artist), norm_title(src_title)
    ca, ct = norm_artist(cand_artist), norm_title(cand_title)
    if not sa or not st or not ca or not ct:
        return 0
    a = 2 if sa == ca else (1 if (sa in ca or ca in sa) else 0)
    ti = 2 if st == ct else (1 if (st in ct or ct in st) else 0)
    if ti == 0 and _censored_match(src_title, cand_title):
        ti = 2  # censored title (F**k You) matched via wildcard
    if a == 0 or ti == 0:
        return 0
    return a * 10 + ti


def variant_penalty(raw_title: str) -> int:
    """Count of variant markers in the raw candidate title (lower = cleaner)."""
    low = (raw_title or "").lower()
    return sum(1 for m in _VARIANT_MARKERS if m in low)


def pick_best(src_artist, src_title, candidates):
    """
    candidates: list of dicts with 'id','artistName','name'. Returns
    (best_or_None, score). Ranks by match_score desc, then fewest variant markers,
    then shortest raw title (closest to the bare song), then original order.
    """
    scored = []
    for idx, c in enumerate(candidates):
        sc = match_score(src_artist, src_title, c.get("artistName", ""), c.get("name", ""))
        if sc > 0:
            scored.append((sc, -variant_penalty(c.get("name", "")), -len(c.get("name", "")), -idx, c))
    if not scored:
        return None, 0
    scored.sort(reverse=True)
    best = scored[0]
    return best[4], best[0]


CONFIDENCE = {22: "exact", 21: "exact-artist", 12: "exact-title", 11: "fuzzy"}

# --------------------------------------------------------------------------- #
#  Source loading
# --------------------------------------------------------------------------- #

_MJ_DB = os.path.expanduser(
    "~/Library/Containers/com.bronty.MusicJournal/Data/Library/Application Support/"
    "MusicJournal/journal.sqlite"
)


def load_from_musicjournal(playlist_name: str) -> list[dict]:
    import sqlite3

    if not os.path.exists(_MJ_DB):
        sys.exit(f"ERROR: MusicJournal DB not found at {_MJ_DB}")
    con = sqlite3.connect(f"file:{_MJ_DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        """SELECT pt.position AS pos, t.artistNames AS artist, t.name AS title,
                  t.albumName AS album, t.spotifyId AS spotifyId
           FROM playlists p
           JOIN playlist_tracks pt ON pt.playlistSpotifyId = p.spotifyId
           JOIN tracks t ON t.spotifyId = pt.trackSpotifyId
           WHERE p.name = ? ORDER BY pt.position""",
        (playlist_name,),
    ).fetchall()
    con.close()
    if not rows:
        sys.exit(f"ERROR: no tracks found for playlist '{playlist_name}' in MusicJournal.")
    return [dict(r) for r in rows]


# --------------------------------------------------------------------------- #
#  Matching against Apple Music
# --------------------------------------------------------------------------- #


def match_all(am, storefront, tracks, throttle):
    matched, unmatched = [], []
    for i, s in enumerate(tracks, 1):
        primary = s["artist"].split(",")[0]
        term = f"{primary} {norm_title(s['title'])}".strip()
        try:
            r = am.get(f"/v1/catalog/{storefront}/search", term=term, types="songs", limit=20)
        except bp.RateLimited:
            raise
        except Exception as e:  # noqa: BLE001
            log.warning("  search failed for %s — %s: %s", s["artist"], s["title"], e)
            r = {}
        cands = ((r.get("results", {}) or {}).get("songs", {}) or {}).get("data", [])
        flat = [{"id": c["id"], **c.get("attributes", {})} for c in cands]
        best, score = pick_best(s["artist"], s["title"], flat)
        rec = {"pos": s.get("pos", i), "artist": s["artist"], "title": s["title"]}
        if best:
            rec.update({
                "status": "matched", "score": score,
                "confidence": CONFIDENCE.get(score, "fuzzy"),
                "apple_id": best["id"], "apple_artist": best.get("artistName"),
                "apple_title": best.get("name"),
            })
            matched.append(rec)
        else:
            rec["status"] = "unmatched"
            unmatched.append(rec)
        if i % 25 == 0 or i == len(tracks):
            log.info("  …matched %d/%d (%d unmatched so far)", i, len(tracks), len(unmatched))
    return matched, unmatched


def write_report(path, playlist_name, matched, unmatched):
    total = len(matched) + len(unmatched)
    by_conf = {}
    for m in matched:
        by_conf[m["confidence"]] = by_conf.get(m["confidence"], 0) + 1
    lines = [
        f"# Sync report: '{playlist_name}' → Apple Music",
        f"_Generated {datetime.datetime.now().isoformat(timespec='seconds')}_",
        "",
        f"**Matched {len(matched)}/{total}**  ·  Unmatched {len(unmatched)}",
        "",
        "Confidence: " + ", ".join(f"{k} {v}" for k, v in sorted(by_conf.items())),
        "",
    ]
    if unmatched:
        lines += ["## ⚠️ Unmatched — need a manual look", "", "| # | Artist | Title |", "|---|---|---|"]
        lines += [f"| {m['pos']} | {m['artist']} | {m['title']} |" for m in unmatched]
        lines.append("")
    # Borderline (fuzzy / exact-title-but-not-artist) matches worth a glance
    border = [m for m in matched if m["score"] < 22]
    if border:
        lines += ["## 🔎 Lower-confidence matches (review)", "",
                  "| Source artist | Source title | → Apple | conf |", "|---|---|---|---|"]
        lines += [f"| {m['artist']} | {m['title']} | {m['apple_artist']} – {m['apple_title']} | {m['confidence']} |"
                  for m in border]
        lines.append("")
    lines += ["## ✅ All matches", "", "| # | Source | → Apple | conf |", "|---|---|---|---|"]
    lines += [f"| {m['pos']} | {m['artist']} – {m['title']} | {m['apple_artist']} – {m['apple_title']} | {m['confidence']} |"
              for m in matched]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


# --------------------------------------------------------------------------- #
#  Main
# --------------------------------------------------------------------------- #


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Sync a Spotify (MusicJournal) playlist to Apple Music with variant-tolerant matching.")
    src = p.add_mutually_exclusive_group()
    src.add_argument("--playlist", help="MusicJournal playlist name to read as the source.")
    src.add_argument("--source", help="A JSON dump of source tracks ([{artist,title,...}]).")
    p.add_argument("--dest", help="Destination Apple Music playlist name (default: '<playlist> [PL]').")
    p.add_argument("--create", action="store_true", help="Create/append the Apple Music playlist (else report only).")
    p.add_argument("--rematch", action="store_true", help="Re-run matching even if a cached matches file exists.")
    p.add_argument("--storefront", default=None)
    p.add_argument("--throttle", type=float, default=0.15)
    p.add_argument("--log-dir", default=os.path.join(bp._HERE, "logs"))
    p.add_argument("--verbose", action="store_true")
    return p.parse_args(argv)


def run(args) -> int:
    if not args.playlist and not args.source:
        sys.exit("ERROR: provide --playlist NAME (MusicJournal) or --source FILE.")
    label = args.playlist or os.path.basename(args.source)
    safe = re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")
    matches_path = os.path.join(bp._HERE, f"matches_{safe}.json")
    report_path = os.path.join(bp._HERE, f"sync_report_{safe}.md")

    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=args.throttle)
    storefront = args.storefront or am.me_storefront() or cfg.get("storefront") or "us"

    if os.path.exists(matches_path) and not args.rematch:
        data = json.load(open(matches_path, encoding="utf-8"))
        matched, unmatched = data["matched"], data["unmatched"]
        log.info("Loaded cached matches: %d matched, %d unmatched (--rematch to redo)",
                 len(matched), len(unmatched))
    else:
        tracks = load_from_musicjournal(args.playlist) if args.playlist else json.load(open(args.source))
        log.info("Source '%s': %d tracks. Matching against Apple Music (storefront %s)…",
                 label, len(tracks), storefront)
        matched, unmatched = match_all(am, storefront, tracks, args.throttle)
        json.dump({"matched": matched, "unmatched": unmatched},
                  open(matches_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    write_report(report_path, label, matched, unmatched)
    total = len(matched) + len(unmatched)
    log.info("RESULT: matched %d/%d, unmatched %d. Report: %s", len(matched), total, len(unmatched), report_path)

    if not args.create:
        log.info("(report only — pass --create to build the Apple Music playlist)")
        return 0

    if not am.has_user_token:
        log.error("No Music User Token — run authorize.py, then re-run with --create.")
        return 3
    dest = args.dest or f"{label} [PL]"
    pid = am.find_library_playlist(dest)
    if not pid:
        pid = am.create_library_playlist(dest, description=f"Synced from Spotify '{label}' — sync_playlist.py")
        log.info("Created playlist '%s' (%s)", dest, pid)
        existing = set()
    else:
        log.info("Found existing playlist '%s' (%s)", dest, pid)
        existing = set(am.library_playlist_catalog_ids(pid))
    manifest = bp.load_manifest(pid)
    existing |= manifest
    desired = [m["apple_id"] for m in matched]
    to_add = bp.plan_additions(desired, existing)
    log.info("Already in '%s': %d   To add: %d", dest, len(existing), len(to_add))
    added = am.add_catalog_songs(pid, to_add)
    bp.save_manifest(pid, existing | set(to_add))
    log.info("Done. Added %d songs to '%s'. (%d/%d source tracks matched)",
             added, dest, len(matched), total)
    return 0


def _ensure_venv() -> None:
    """Re-exec THIS script inside the shared .venv (build_playlist's bootstrap
    would re-exec build_playlist.py, not us — hence our own)."""
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


def main() -> int:
    args = parse_args()
    _ensure_venv()
    log_path = bp.setup_logging(args.log_dir, debug_to_console=args.verbose)
    log.info("=== sync_playlist start === (log: %s)", log_path)
    try:
        rc = run(args)
    except bp.RateLimited as e:
        log.error("RATE LIMITED (HTTP 429), retry-after %ss. Stopping.", e.retry_after)
        return 4
    except Exception:  # noqa: BLE001
        log.exception("FATAL: sync failed")
        return 1
    log.info("=== sync_playlist end (rc=%d) ===", rc)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
