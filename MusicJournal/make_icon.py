#!/usr/bin/env python3
"""Generate MusicJournal app icon — dark green gradient, vinyl + pen design."""

import math
import os
from PIL import Image, ImageDraw

SIZE = 1024
ICON_DIR = "Sources/MusicJournal/Resources/Assets.xcassets/AppIcon.appiconset"


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def make_icon(size=SIZE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- Background gradient (dark forest green → near-black) ---
    top_col = (18, 52, 30)      # deep forest green
    bot_col = (8, 14, 10)       # almost black
    for y in range(size):
        t = y / size
        col = lerp_color(top_col, bot_col, t)
        draw.line([(0, y), (size, y)], fill=col + (255,))

    cx, cy = size // 2, size // 2

    # --- Vinyl record ---
    rec_r = int(size * 0.38)
    # Outer ring - dark charcoal
    draw.ellipse(
        [cx - rec_r, cy - rec_r, cx + rec_r, cy + rec_r],
        fill=(28, 28, 32, 255)
    )
    # Groove rings
    for i, frac in enumerate([0.95, 0.85, 0.75, 0.65]):
        r = int(rec_r * frac)
        alpha = 60 + i * 15
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            outline=(80, 80, 90, alpha), width=2
        )
    # Label (centre circle) - warm amber/gold gradient effect
    label_r = int(rec_r * 0.38)
    # Outer label glow
    for i in range(6):
        r = label_r + (5 - i) * 3
        a = int(40 + i * 15)
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(180, 130, 40, a)
        )
    draw.ellipse(
        [cx - label_r, cy - label_r, cx + label_r, cy + label_r],
        fill=(210, 160, 50, 255)
    )
    # Shine highlight on label
    draw.ellipse(
        [cx - label_r + 8, cy - label_r + 8,
         cx + label_r - 24, cy + label_r - 24],
        fill=(240, 200, 100, 80)
    )
    # Centre hole
    hole_r = int(rec_r * 0.06)
    draw.ellipse(
        [cx - hole_r, cy - hole_r, cx + hole_r, cy + hole_r],
        fill=(8, 14, 10, 255)
    )

    # --- Music note on the label ---
    # Draw a quarter note: filled oval head + stem + flag
    note_scale = label_r * 0.45
    note_cx = cx - int(note_scale * 0.15)
    note_cy = cy + int(note_scale * 0.10)

    # Note head (tilted ellipse approximated)
    nh_w, nh_h = int(note_scale * 0.62), int(note_scale * 0.48)
    draw.ellipse(
        [note_cx - nh_w, note_cy - nh_h,
         note_cx + nh_w, note_cy + nh_h],
        fill=(40, 25, 5, 220)
    )
    # Stem
    stem_x = note_cx + nh_w - 4
    stem_top = note_cy - int(note_scale * 1.6)
    draw.rectangle(
        [stem_x - 5, stem_top, stem_x + 5, note_cy],
        fill=(40, 25, 5, 220)
    )
    # Flag
    flag_pts = [
        (stem_x, stem_top),
        (stem_x + int(note_scale * 0.6), stem_top + int(note_scale * 0.4)),
        (stem_x + int(note_scale * 0.3), stem_top + int(note_scale * 0.7)),
        (stem_x, stem_top + int(note_scale * 0.5)),
    ]
    draw.polygon(flag_pts, fill=(40, 25, 5, 220))

    # --- Pen / quill in bottom-right, overlapping record edge ---
    pen_x1 = cx + int(rec_r * 0.55)
    pen_y1 = cy + int(rec_r * 0.55)
    pen_len = int(size * 0.32)
    angle = math.radians(225)   # pointing bottom-left
    pen_x2 = pen_x1 + int(pen_len * math.cos(angle))
    pen_y2 = pen_y1 + int(pen_len * math.sin(angle))

    perp = math.radians(225 + 90)
    pw = int(size * 0.018)

    # Pen body (soft white)
    draw.line([(pen_x1, pen_y1), (pen_x2, pen_y2)],
              fill=(230, 225, 215, 230), width=pw)

    # Pen nib (gold triangle)
    nib_len = int(size * 0.055)
    nib_tip_x = pen_x2 + int(nib_len * math.cos(angle))
    nib_tip_y = pen_y2 + int(nib_len * math.sin(angle))
    nib_w = pw * 1.2
    left_x = pen_x2 + int(nib_w * math.cos(perp))
    left_y = pen_y2 + int(nib_w * math.sin(perp))
    right_x = pen_x2 - int(nib_w * math.cos(perp))
    right_y = pen_y2 - int(nib_w * math.sin(perp))
    draw.polygon(
        [(nib_tip_x, nib_tip_y), (left_x, left_y), (right_x, right_y)],
        fill=(210, 160, 50, 255)
    )

    # Pen cap end (rounded tip top)
    cap_r = pw
    draw.ellipse(
        [pen_x1 - cap_r, pen_y1 - cap_r,
         pen_x1 + cap_r, pen_y1 + cap_r],
        fill=(200, 195, 185, 230)
    )

    # --- Subtle glow behind record ---
    glow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for i in range(20):
        r = rec_r + (20 - i) * 4
        a = int(4 + i * 1.5)
        gd.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            outline=(60, 180, 90, a), width=6
        )
    img = Image.alpha_composite(img, glow_layer)

    return img


def save_sizes(base_img):
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    os.makedirs(ICON_DIR, exist_ok=True)
    for s in sizes:
        resized = base_img.resize((s, s), Image.LANCZOS)
        resized.save(os.path.join(ICON_DIR, f"icon_{s}x{s}.png"))
    print("Icons saved.")


def write_contents_json():
    json = '''{
  "images" : [
    { "filename" : "icon_16x16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64x64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024x1024.png","idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
'''
    with open(os.path.join(ICON_DIR, "Contents.json"), "w") as f:
        f.write(json)
    print("Contents.json updated.")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    img = make_icon()
    save_sizes(img)
    write_contents_json()
    print("Done! Rebuild MusicJournal.xcodeproj to pick up the new icon.")
