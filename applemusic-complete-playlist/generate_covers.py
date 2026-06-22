#!/usr/bin/env python3
"""generate_covers.py — deterministic code-art cover images for every `[PL]` playlist.

Apple won't let custom playlist artwork be set via API or AppleScript, so these are
generated to a folder for manual application in Music.app. Design is deterministic
(same name -> same image): a category-derived gradient, a faint motif word, the
playlist title (auto-fit) and the song count. Requires Pillow.

Output: ~/Downloads/applemusic-complete-playlist/covers/<safe-name>.png
"""
from __future__ import annotations

import hashlib
import os
import re

from PIL import Image, ImageDraw, ImageFont

SIZE = 1200
OUT = os.path.expanduser("~/Downloads/applemusic-complete-playlist/covers")

def _font(size, bold=True):
    for path, idx in [("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
                      ("/System/Library/Fonts/SFNS.ttf", 0),
                      ("/System/Library/Fonts/Supplemental/Futura.ttc", 0)]:
        try:
            return ImageFont.truetype(path, size, index=idx)
        except Exception:
            continue
    return ImageFont.load_default()

# category -> (top color, bottom color, motif word)
PALETTE = {
    "70s":  ((232, 93, 4),   (106, 4, 15),    "70s"),
    "80s":  ((255, 0, 110),  (58, 12, 163),   "80s"),
    "90s":  ((6, 214, 160),  (7, 59, 76),     "90s"),
    "2000s":((67, 97, 238),  (34, 7, 80),     "00s"),
    "2010s":((247, 37, 133), (76, 9, 138),    "10s"),
    "country": ((200, 134, 11), (60, 40, 25), "COUNTRY"),
    "ac":   ((229, 152, 155),(80, 60, 90),    "AC"),
    "metal":((141, 153, 174),(11, 9, 10),     "METAL"),
    "rock": ((230, 57, 70),  (29, 53, 87),    "ROCK"),
    "classical": ((212, 175, 55), (20, 33, 61), "CLASSICAL"),
    "standalone":((42, 157, 143),(38, 70, 70), "♪"),
}
ARTIST_PALETTES = [
    ((239, 71, 111), (32, 6, 38)), ((255, 159, 28), (40, 20, 0)),
    ((6, 214, 160), (5, 40, 35)),  ((17, 138, 178), (5, 20, 45)),
    ((155, 93, 229), (25, 5, 50)), ((255, 99, 146), (40, 5, 30)),
    ((46, 196, 182), (10, 40, 40)),((255, 209, 102), (45, 30, 0)),
]

def categorize(name: str):
    """-> (palette_tuple, motif_word, tag, title)."""
    title = re.sub(r"\s*\[PL\]$", "", name)
    m = re.match(r"^(70s|80s|90s|2000s|2010s)", name)
    dec = m.group(1) if m else None
    if dec and "Country" in name:
        p = PALETTE["country"]; return ((p[0], p[1]), dec, "Country", title)
    if dec and "Adult Contemporary" in name:
        p = PALETTE["ac"]; return ((p[0], p[1]), dec, "Adult Contemporary", title)
    if dec and name.endswith("— Metal [PL]"):
        p = PALETTE["metal"]; return ((p[0], p[1]), dec, "Metal", title)
    if dec and name.endswith("— Rock [PL]"):
        p = PALETTE["rock"]; return ((p[0], p[1]), dec, "Rock", title)
    if dec:
        p = PALETTE[dec]; return ((p[0], p[1]), p[2], "Decade", title)
    if name == "Metal — Complete [PL]" or title.lower().endswith(("metal", "metalcore", "deathcore")):
        p = PALETTE["metal"]; return ((p[0], p[1]), "METAL", "Metal", title)
    if "Classical Renditions" in name:
        p = PALETTE["classical"]; return ((p[0], p[1]), "♬", "Classical", title)
    if name in ("Life in Music [PL]", "Brent Mason — Played On [PL]"):
        p = PALETTE["standalone"]; return ((p[0], p[1]), "♪", "Collection", title)
    # artist complete -> hash-derived palette + initials motif
    h = int(hashlib.md5(name.encode()).hexdigest(), 16)
    pal = ARTIST_PALETTES[h % len(ARTIST_PALETTES)]
    initials = "".join(w[0] for w in re.sub(r"Complete$", "", title).split()[:3]).upper()
    return (pal, initials or "★", "Artist", title)

def gradient(c0, c1):
    img = Image.new("RGB", (SIZE, SIZE), c0)
    top = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        top.putpixel((0, y), tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)))
    return top.resize((SIZE, SIZE))

def fit_font(draw, text_lines, max_w, max_h, start=150):
    size = start
    while size > 28:
        f = _font(size)
        widths = [draw.textbbox((0, 0), ln, font=f)[2] for ln in text_lines]
        line_h = draw.textbbox((0, 0), "Ag", font=f)[3] + 12
        if max(widths) <= max_w and line_h * len(text_lines) <= max_h:
            return f, line_h
        size -= 6
    return _font(28), draw.textbbox((0, 0), "Ag", font=_font(28))[3] + 12

def wrap(title, draw, font, max_w):
    words, lines, cur = title.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textbbox((0, 0), t, font=font)[2] <= max_w or not cur:
            cur = t
        else:
            lines.append(cur); cur = w
    if cur:
        lines.append(cur)
    return lines

def render(name, count):
    (c0, c1), motif, tag, title = categorize(name)
    img = gradient(c0, c1)
    d = ImageDraw.Draw(img, "RGBA")
    # faint oversized motif, top-right
    mf = _font(520)
    d.text((SIZE - 40, -60), motif, font=mf, fill=(255, 255, 255, 28), anchor="ra")
    # title, auto-fit & wrapped, lower-left
    margin = 90
    probe = wrap(title, d, _font(110), SIZE - 2 * margin)
    font, line_h = fit_font(d, probe, SIZE - 2 * margin, 560)
    lines = wrap(title, d, font, SIZE - 2 * margin)
    y = SIZE - margin - line_h * len(lines) - 130
    for ln in lines:
        d.text((margin, y), ln, font=font, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 90))
        y += line_h
    # accent bar + count/tag
    d.rectangle([margin, SIZE - 175, margin + 120, SIZE - 168], fill=(255, 255, 255, 230))
    sub = _font(46, bold=True)
    d.text((margin, SIZE - 150), f"{count:,} songs  ·  {tag}", font=sub, fill=(255, 255, 255, 235))
    return img

def safe(name):
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")[:120] + ".png"

def main():
    import argparse, json
    p = argparse.ArgumentParser(description="Generate code-art covers for [PL] playlists.")
    p.add_argument("--inventory", default="/tmp/playlist_inventory.json",
                   help="JSON [{name,count}] (else queries the library).")
    p.add_argument("--limit", type=int, default=0, help="only first N (for sampling).")
    args = p.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if os.path.exists(args.inventory):
        rows = json.load(open(args.inventory))
    else:
        import build_playlist as bp
        cfg = bp.load_config(); am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=0.04)
        rows = [{"name": pl["attributes"]["name"], "count": len(bp.load_manifest(pl["id"]))}
                for pl in am.get_paginated("/v1/me/library/playlists", limit=100)
                if pl.get("attributes", {}).get("name", "").endswith("[PL]")]
    if args.limit:
        rows = rows[:args.limit]
    for r in rows:
        render(r["name"], r["count"]).save(os.path.join(OUT, safe(r["name"])), "PNG")
    print(f"Wrote {len(rows)} covers to {OUT}")

if __name__ == "__main__":
    main()
