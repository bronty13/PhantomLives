#!/usr/bin/env python3
"""describe.py — generate a rich, human description for one of our `[PL]` playlists.

Pure function of (name, song_count): categorize by the naming convention and return
detailed text. Used by enrich_descriptions.py (sets them via AppleScript, which —
unlike the REST API — CAN update an existing library playlist's description and
syncs the change to iCloud).
"""
from __future__ import annotations

import re

GENRE_BLURB = ("Pop, Rock, Alternative and Hip-Hop/R&B (Billboard Year-End Hot 100), "
               "plus Adult Contemporary #1s and editorial Rock and Metal")

def describe(name: str, count: int) -> str:
    n = f"{count:,}"

    # --- decade collection (order matters: specific before the artist-complete fallback) ---
    m = re.match(r"^(70s|80s|90s|2000s|2010s) — (\d{4}) \[PL\]$", name)
    if m:
        d, y = m.groups()
        return (f"The biggest songs of {y} — {n} tracks from the Billboard Year-End "
                f"Hot 100 plus that year's Adult Contemporary #1s. Part of the {d} collection.")
    m = re.match(r"^(70s|80s|90s|2000s|2010s) — Complete \[PL\]$", name)
    if m:
        d = m.group(1)
        return (f"Every {d} hit in one list — {n} songs across {GENRE_BLURB}, built from the "
                f"charts (≈96–99% of the decade's Hot 100). See the per-year “{d} — YYYY” lists; "
                f"country lives in the separate “{d} Country” set.")
    m = re.match(r"^(70s|80s|90s|2000s|2010s) Country — (\d{4}) \[PL\]$", name)
    if m:
        d, y = m.groups()
        return (f"Country hits of {y} — {n} songs from Billboard's Year-End Hot Country "
                f"Songs and the weekly Hot Country #1s. Part of the {d} Country set.")
    m = re.match(r"^(70s|80s|90s|2000s|2010s) Country — Complete \[PL\]$", name)
    if m:
        d = m.group(1)
        return (f"Every year-end and #1 country hit of the {d} — {n} songs from Billboard's "
                f"Year-End Hot Country Songs and weekly Hot Country #1s. A separate set from "
                f"the main {d} collection.")
    m = re.match(r"^(70s|80s|90s|2000s|2010s) Country — Essentials \[PL\]$", name)
    if m:
        return f"{n} essential {m.group(1)} country songs (Apple Music editorial)."
    m = re.match(r"^(70s|80s|90s|2000s|2010s) Adult Contemporary — (\d{4}) \[PL\]$", name)
    if m:
        d, y = m.groups()
        return f"The Adult Contemporary #1 singles of {y} — {n} chart-toppers. Part of the {d} collection."
    m = re.match(r"^(70s|80s|90s|2000s|2010s) Adult Contemporary — Complete \[PL\]$", name)
    if m:
        d = m.group(1)
        return (f"The {d} Adult Contemporary #1 singles — {n} chart-toppers from Billboard's "
                f"weekly AC chart, the soft-rock and ballad hits that defined the era.")
    m = re.match(r"^(70s|80s|90s|2000s|2010s) — Metal \[PL\]$", name)
    if m:
        return f"{n} essential {m.group(1)} metal and hard-rock tracks (Apple Music editorial)."
    m = re.match(r"^(70s|80s|90s|2000s|2010s) — Rock \[PL\]$", name)
    if m:
        return f"{n} essential {m.group(1)} rock tracks (Apple Music editorial)."

    # --- metal collection ---
    if name == "Metal — Complete [PL]":
        return (f"{n} essential metal tracks spanning thrash, death, black, doom, power, glam, "
                f"progressive, metalcore and more — Apple Music's sub-genre essentials, deduped. "
                f"See the per-style streams and the “<Band> Complete” discographies for full depth.")
    m = re.match(r"^(.+?) \[PL\]$", name)
    if m and m.group(1).lower().endswith(("metal", "metalcore", "deathcore")):
        style = m.group(1)
        return f"{n} essential {style.lower()} tracks — Apple Music editorial, the sub-genre's defining songs."

    # --- classical renditions ---
    m = re.match(r"^(.+?) — Classical Renditions \[PL\]$", name)
    if m:
        a = m.group(1)
        return (f"{n} classical and instrumental renditions of {a} songs — string-quartet, piano "
                f"and orchestral tribute recordings.")

    # --- standalone ---
    if name == "Life in Music [PL]":
        return (f"A legacy music diary — {n} songs synced from Spotify and matched to Apple Music. "
                f"The personal soundtrack the whole archive is built around.")
    if name == "Brent Mason — Played On [PL]":
        return (f"{n} songs the Nashville session guitarist Brent Mason played on — assembled from a "
                f"curated discography and matched to Apple Music. His playing across decades of country radio.")

    # --- artist-complete fallback ---
    m = re.match(r"^(.+?) Complete \[PL\]$", name)
    if m:
        a = m.group(1)
        return (f"Every available {a} recording plus guest features — {n} tracks. Flavor A: every "
                f"version, live cut and remaster, not deduped by title. Re-runnable to stay current.")

    return f"{n} songs."
