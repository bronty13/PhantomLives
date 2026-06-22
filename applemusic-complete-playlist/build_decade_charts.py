#!/usr/bin/env python3
"""
build_decade_charts.py — build CHART-ACCURATE decade playlists for Apple Music.

Unlike build_decade.py (which copies Apple's own editorial "<Genre> Hits: YYYY"
lists), this builds each decade from independent Billboard CHART data, so coverage
is measured against the charts, not Apple's curation — typically ~95-98% of the
Year-End Hot 100 vs ~60% for editorial-only.

Sources per genre:
  POP      Billboard Year-End Hot 100            (Wikipedia, ~100/yr)         -> fuzzy match
  COUNTRY  Billboard Year-End Hot Country Songs  (Billboard.com)  ∪
           weekly Hot Country #1s                (Wikipedia)                  -> fuzzy match
  AC       weekly Adult Contemporary #1s         (Wikipedia, ~20/yr)          -> fuzzy match
  METAL    "<dec> Metal/Thrash/Hard Rock Essentials"  (Apple editorial)       -> catalog ids
  ROCK     "<dec> Rock Essentials"                    (Apple editorial)       -> catalog ids
(Billboard never charted metal/rock singles in these eras, so those use Apple
editorial; AC's Billboard year-end isn't archived online, so AC uses weekly #1s.)

Each chart genre gets a per-year set ("90s — 1994 [PL]", "90s Country — 1994 [PL]",
"90s Adult Contemporary — 1994 [PL]") and a master ("90s — Complete [PL]"); AC,
metal and rock also FOLD into the decade master (and AC into the decade per-year
lists, since AC #1s carry a year). Idempotent (per-playlist manifest) and crash-
safe (per-batch manifest checkpoint, via build_playlist.add_catalog_songs).

Usage:
  python3 build_decade_charts.py --decade 90s --dry-run
  python3 build_decade_charts.py --decade 90s --only pop,country,ac
  python3 build_decade_charts.py --decade 90s
"""
from __future__ import annotations

import argparse
import html as _html
import os
import re
import sys
import time
import urllib.parse

import build_playlist as bp
import build_decade as bd
import sync_playlist as sp

log = bp.log

BROWSER_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")
WIKI_UA = "applemusic-complete-playlist/1.0 (robert.olen@gmail.com)"

GENRES = ("pop", "country", "ac", "metal", "rock")

# Apple editorial "Essentials" sources for the un-charted genres, per decade.
ESSENTIALS = {
    "70s":   {"metal": ["70s Metal Essentials", "70s Hard Rock Essentials"],
              "rock":  ["70s Rock Essentials"]},
    "80s":   {"metal": ["80s Metal Essentials", "80s Thrash Essentials", "80s Hard Rock Essentials"],
              "rock":  ["80s Rock Essentials"]},
    "90s":   {"metal": ["90s Metal Essentials", "90s Thrash Essentials", "90s Hard Rock Essentials"],
              "rock":  ["90s Rock Essentials"]},
    "2000s": {"metal": ["2000s Metal Essentials", "2000s Thrash Essentials",
                        "2000s Hard Rock Essentials", "Metalcore Essentials"],
              "rock":  ["2000s Rock Essentials"]},
    "2010s": {"metal": ["2010s Metal Essentials", "2010s Thrash Essentials",
                        "2010s Hard Rock Essentials"],
              "rock":  ["2010s Rock Essentials"]},
}

def decade_years(decade: str) -> range:
    start = int(decade[:4]) if decade[0].isdigit() and len(decade) >= 4 else 1900 + int(decade[:2])
    return range(start, start + 10)

# --------------------------------------------------------------------------- #
#  HTML parsing (pure — takes html text, no network; unit-tested)
# --------------------------------------------------------------------------- #

def _clean(cell: str) -> str:
    cell = re.sub(r"<(style|script)\b.*?</\1>", "", cell, flags=re.S)
    cell = re.sub(r"<[^>]+>", "", cell)
    cell = re.sub(r"\[[0-9a-z]+\]", "", cell)      # [13] / [a] footnotes
    return _html.unescape(cell).strip()

def parse_hot100_table(html: str) -> list[dict]:
    """Year-End Hot 100 (Wikipedia): a ranked table of No. | Title | Artist."""
    m = re.search(r"<table[^>]*wikitable.*?</table>", html, re.S)
    if not m:
        return []
    out = []
    for r in re.findall(r"<tr>(.*?)</tr>", m.group(0), re.S):
        cells = [_clean(c) for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", r, re.S)]
        if len(cells) >= 3 and cells[0].isdigit():
            out.append({"artist": cells[2], "title": cells[1].strip().strip('"')})
    return out

def parse_quoted_title_tables(html: str) -> list[dict]:
    """Weekly-#1 style lists (country / AC): scan ALL wikitables and pull rows that
    have a quoted-title cell followed by an artist cell. Scanning every table (not
    just the first) is what makes legend/key tables — e.g. 1970 AC's leading
    '† Indicates…' table — harmless. De-dupes by (title, artist)."""
    out, seen = [], set()
    for tbl in re.findall(r"<table[^>]*wikitable.*?</table>", html, re.S):
        for r in re.findall(r"<tr>(.*?)</tr>", tbl, re.S):
            texts = [_clean(c) for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", r, re.S)]
            ti = next((i for i, t in enumerate(texts) if t.startswith('"')), None)
            if ti is None or ti + 1 >= len(texts):
                continue
            title, artist = texts[ti].strip().strip('"').strip(), texts[ti + 1].strip()
            k = (title.lower(), artist.lower())
            if title and artist and k not in seen:
                seen.add(k); out.append({"artist": artist, "title": title})
    return out

def parse_billboard_yearend(html: str) -> list[dict]:
    """Billboard.com year-end chart: split on the row container, take each row's
    title (<h3 c-title>) + first label (artist)."""
    out, seen = [], set()
    for r in re.split(r"o-chart-results-list-row", html):
        tm = re.search(r"c-title[^>]*>(.*?)</h3>", r, re.S)
        if not tm:
            continue
        title = _clean(tm.group(1))
        am = re.search(r"c-label[^>]*>(.*?)</span>", r[tm.end():], re.S)
        artist = _clean(am.group(1)) if am else ""
        k = (title.lower(), artist.lower())
        if title and artist and not title.lower().startswith(("gains", "additional")) and k not in seen:
            seen.add(k); out.append({"artist": artist, "title": title})
    return out

def era_plausible(rows: list[dict], year: int) -> bool:
    """Guard against Billboard.com serving the *current* chart as a fallback for a
    historical year-end that doesn't exist: a real pre-2000 chart should not be
    dominated by obviously-modern acts. Heuristic, conservative."""
    if not rows or year >= 2000:
        return bool(rows)
    modern = ("Maneskin", "Evanescence", "Greta Van Fleet", "Five Finger Death Punch",
              "Olivia Dean", "Alex Warren", "Sabrina Carpenter", "Doja Cat", "HUNTR/X")
    hits = sum(1 for r in rows if any(mm in r["artist"] for mm in modern))
    return hits < max(2, len(rows) // 10)

# --------------------------------------------------------------------------- #
#  Fetch wrappers (network)
# --------------------------------------------------------------------------- #

def _get(url: str, ua: str) -> str:
    import requests
    return requests.get(url, headers={"User-Agent": ua}, timeout=30).text

def fetch_hot100(year: int) -> list[dict]:
    u = "https://en.wikipedia.org/wiki/" + urllib.parse.quote(f"Billboard_Year-End_Hot_100_singles_of_{year}")
    return parse_hot100_table(_get(u, WIKI_UA))

def fetch_country(year: int) -> list[dict]:
    ye_html = _get(f"https://www.billboard.com/charts/year-end/{year}/hot-country-songs/", BROWSER_UA)
    ye = parse_billboard_yearend(ye_html)
    if not era_plausible(ye, year):
        log.warning("  country year-end %d looked like a current-chart fallback — dropping it", year)
        ye = []
    u = "https://en.wikipedia.org/wiki/" + urllib.parse.quote(f"List_of_Hot_Country_Singles_number_ones_of_{year}")
    no1 = parse_quoted_title_tables(_get(u, WIKI_UA))
    seen, uni = set(), []
    for e in ye + no1:
        k = (sp.norm_title(e["title"]), sp.norm_artist(e["artist"]))
        if k not in seen:
            seen.add(k); uni.append(e)
    return uni

def fetch_ac(year: int) -> list[dict]:
    page = f"List_of_number-one_adult_contemporary_singles_of_{year}_(U.S.)"
    return parse_quoted_title_tables(_get("https://en.wikipedia.org/wiki/" + urllib.parse.quote(page), WIKI_UA))

# --------------------------------------------------------------------------- #
#  Build helpers
# --------------------------------------------------------------------------- #

def append(am, name: str, ids: list[str], *, create_desc: str | None, dry: bool) -> int:
    desired = list(dict.fromkeys(ids))
    if dry:
        return len(desired)
    pid = am.find_library_playlist(name)
    if not pid:
        if create_desc is None:
            log.warning("  %s missing and no-create — skipped", name)
            return 0
        pid = am.create_library_playlist(name, description=create_desc)
        existing = set()
    else:
        existing = set(am.library_playlist_catalog_ids(pid)) | bp.load_manifest(pid)
    to_add = bp.plan_additions(desired, existing)
    added = am.add_catalog_songs(pid, to_add, manifest_base=existing) if to_add else 0
    bp.save_manifest(pid, existing | set(to_add))
    return added

def match_rows(am, sf, rows, throttle):
    matched, unmatched = sp.match_all(am, sf, rows, throttle)
    return [m["apple_id"] for m in matched], matched, unmatched

def build_chart_genre(am, sf, decade, prefix, years, fetch, label, throttle, dry,
                      fold_master=None, fold_year_tmpl=None):
    """Build a per-year set + master for a chart genre. Optionally fold matched ids
    into a decade master and/or its per-year lists (used by AC)."""
    master_ids, total_matched, total_rows = [], 0, 0
    for y in years:
        rows = fetch(y)
        time.sleep(throttle)
        for r in rows:
            r["year"] = y
        total_rows += len(rows)
        if not rows:
            log.info("  %s %d: no chart rows", label, y)
            continue
        ids, matched, unmatched = match_rows(am, sf, rows, throttle)
        total_matched += len(matched)
        master_ids += ids
        added = append(am, f"{prefix}{y} [PL]", ids, create_desc=f"{decade} {label} {y} (chart-built)", dry=dry)
        if fold_year_tmpl:
            append(am, fold_year_tmpl.format(y=y), ids, create_desc=None, dry=dry)
        log.info("  %s %d: %d rows → %d matched → +%d", label, y, len(rows), len(matched), added)
    madd = append(am, f"{prefix}Complete [PL]", master_ids,
                  create_desc=f"{decade} {label} — chart-built master", dry=dry)
    if fold_master:
        append(am, fold_master, master_ids, create_desc=None, dry=dry)
    log.info("%s%s: %d/%d matched across decade → master +%d",
             prefix, "Complete [PL]", total_matched, total_rows, madd)
    return master_ids

def build_editorial_genre(am, sf, decade, stream_name, sources, fold_master, dry):
    ids = []
    for src in sources:
        spid = bd.find_catalog_playlist(am, sf, src)
        if not spid:
            log.warning("  editorial '%s' not found", src)
            continue
        sids = bd.fetch_song_ids(am, sf, spid)
        ids += sids
        log.info("  %s: %d songs", src, len(sids))
    ids = list(dict.fromkeys(ids))
    a1 = append(am, stream_name, ids, create_desc=f"{decade} {stream_name} — editorial essentials", dry=dry)
    a2 = append(am, fold_master, ids, create_desc=None, dry=dry)
    log.info("%s: +%d (separate), folded into %s: +%d", stream_name, a1, fold_master, a2)

# --------------------------------------------------------------------------- #
#  Orchestration
# --------------------------------------------------------------------------- #

def run(args) -> int:
    cfg = bp.load_config()
    am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=args.throttle)
    if not args.dry_run and not am.has_user_token:
        log.error("No Music User Token — run authorize.py first.")
        return 3
    sf = args.storefront or am.me_storefront() or cfg.get("storefront") or "us"
    decade = args.decade
    years = decade_years(decade)
    only = set(args.only.split(",")) if args.only else set(GENRES)
    dec_master = f"{decade} — Complete [PL]"
    dec_year_t = f"{decade} — {{y}} [PL]"

    if "pop" in only:
        log.info("=== POP (Year-End Hot 100) ===")
        build_chart_genre(am, sf, decade, f"{decade} — ", years, fetch_hot100, "Hot 100",
                          args.throttle, args.dry_run)
    if "country" in only:
        log.info("=== COUNTRY (year-end ∪ #1s) ===")
        build_chart_genre(am, sf, decade, f"{decade} Country — ", years, fetch_country, "Country",
                          args.throttle, args.dry_run)
    if "ac" in only:
        log.info("=== ADULT CONTEMPORARY (#1s) — folds into decade master ===")
        build_chart_genre(am, sf, decade, f"{decade} Adult Contemporary — ", years, fetch_ac, "AC",
                          args.throttle, args.dry_run,
                          fold_master=dec_master, fold_year_tmpl=dec_year_t)
    ess = ESSENTIALS.get(decade, {})
    if "metal" in only and ess.get("metal"):
        log.info("=== METAL (editorial) — folds into decade master ===")
        build_editorial_genre(am, sf, decade, f"{decade} — Metal [PL]", ess["metal"], dec_master, args.dry_run)
    if "rock" in only and ess.get("rock"):
        log.info("=== ROCK (editorial) — folds into decade master ===")
        build_editorial_genre(am, sf, decade, f"{decade} — Rock [PL]", ess["rock"], dec_master, args.dry_run)

    if not args.dry_run:
        bp.warn_library_headroom(am)
    return 0

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

def main() -> int:
    p = argparse.ArgumentParser(description="Build chart-accurate decade playlists (pop/country/AC + metal/rock).")
    p.add_argument("--decade", required=True, choices=sorted(ESSENTIALS))
    p.add_argument("--only", default=None, help="comma list of genres: pop,country,ac,metal,rock")
    p.add_argument("--storefront", default=None)
    p.add_argument("--throttle", type=float, default=0.15)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--log-dir", default=os.path.join(bp._HERE, "logs"))
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args()
    _ensure_venv()
    log_path = bp.setup_logging(args.log_dir, debug_to_console=args.verbose)
    log.info("=== build_decade_charts '%s' start === (log: %s)", args.decade, log_path)
    try:
        rc = run(args)
    except bp.RateLimited as e:
        log.error("RATE LIMITED (429) retry-after %ss.", e.retry_after)
        return 4
    except Exception:  # noqa: BLE001
        log.exception("FATAL: build_decade_charts failed")
        return 1
    log.info("=== build_decade_charts end (rc=%d) ===", rc)
    return rc

if __name__ == "__main__":
    raise SystemExit(main())
