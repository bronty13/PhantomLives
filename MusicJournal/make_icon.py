#!/usr/bin/env python3
"""Generate MusicJournal app icon — squircle background, green gradient,
faint journal lines, single bold eighth note centered on top.

Designed to read clearly down to 16x16 in the Dock and Finder.
"""

import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
ICON_DIR = "Sources/MusicJournal/Resources/Assets.xcassets/AppIcon.appiconset"

GREEN_TOP = (34, 100, 60)      # vivid forest green
GREEN_BOTTOM = (8, 22, 14)     # near-black
NOTE_COLOR = (248, 244, 228)   # warm cream
LINE_RGBA = (255, 255, 255, 32)
SQUIRCLE_RADIUS_FRAC = 0.225   # macOS Big Sur+ corner ratio


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def squircle_mask(size, radius_frac=SQUIRCLE_RADIUS_FRAC):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * radius_frac)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask


def gradient_bg(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)],
               fill=lerp_color(GREEN_TOP, GREEN_BOTTOM, t))
    return img


def add_top_highlight(canvas, mask, size):
    """Apple-style soft top sheen."""
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(hl)
    r = int(size * 0.22)
    d.rounded_rectangle(
        [int(size * 0.04), int(size * 0.04),
         int(size * 0.96), int(size * 0.50)],
        radius=r, fill=(255, 255, 255, 22),
    )
    hl = hl.filter(ImageFilter.GaussianBlur(size * 0.025))
    clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    clipped.paste(hl, (0, 0), mask)
    return Image.alpha_composite(canvas, clipped)


def draw_journal_lines(canvas, size):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    n_lines = 8
    margin_x = int(size * 0.14)
    spacing = int(size * 0.085)
    thickness = max(1, size // 320)
    total_h = (n_lines - 1) * spacing
    start_y = (size - total_h) // 2
    for i in range(n_lines):
        y = start_y + i * spacing
        d.line([(margin_x, y), (size - margin_x, y)],
               fill=LINE_RGBA, width=thickness)
    return Image.alpha_composite(canvas, layer)


def draw_eighth_note(canvas, size):
    """Stylized eighth note: tilted oval head, vertical stem, curvy flag."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Note head — drawn upright on its own canvas, then rotated for tilt
    head_w = int(size * 0.30)
    head_h = int(size * 0.22)
    pad = int(max(head_w, head_h) * 1.4)
    head_img = Image.new("RGBA", (pad * 2, pad * 2), (0, 0, 0, 0))
    hd = ImageDraw.Draw(head_img)
    hd.ellipse(
        [pad - head_w // 2, pad - head_h // 2,
         pad + head_w // 2, pad + head_h // 2],
        fill=NOTE_COLOR,
    )
    head_img = head_img.rotate(22, resample=Image.BICUBIC)

    head_cx = int(size * 0.42)
    head_cy = int(size * 0.66)
    layer.paste(head_img, (head_cx - pad, head_cy - pad), head_img)

    nd = ImageDraw.Draw(layer)

    # Stem
    stem_w = int(size * 0.038)
    stem_x = head_cx + int(head_w * 0.42)
    stem_top = int(size * 0.20)
    nd.rectangle(
        [stem_x - stem_w // 2, stem_top,
         stem_x + stem_w // 2, head_cy + int(size * 0.01)],
        fill=NOTE_COLOR,
    )

    # Flag — curvy banner off the top of the stem
    fx = stem_x + stem_w // 2 - 2
    fy = stem_top
    s = size
    flag_pts = [
        (fx, fy),
        (fx + int(s * 0.06),  fy + int(s * 0.015)),
        (fx + int(s * 0.13),  fy + int(s * 0.07)),
        (fx + int(s * 0.165), fy + int(s * 0.16)),
        (fx + int(s * 0.155), fy + int(s * 0.235)),
        (fx + int(s * 0.115), fy + int(s * 0.27)),
        (fx + int(s * 0.115), fy + int(s * 0.245)),
        (fx + int(s * 0.135), fy + int(s * 0.215)),
        (fx + int(s * 0.135), fy + int(s * 0.155)),
        (fx + int(s * 0.105), fy + int(s * 0.09)),
        (fx + int(s * 0.045), fy + int(s * 0.045)),
        (fx,                  fy + int(s * 0.03)),
    ]
    nd.polygon(flag_pts, fill=NOTE_COLOR)

    return Image.alpha_composite(canvas, layer)


def make_icon(size=SIZE):
    mask = squircle_mask(size)
    bg = gradient_bg(size).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(bg, (0, 0), mask)

    canvas = add_top_highlight(canvas, mask, size)
    canvas = draw_journal_lines(canvas, size)
    canvas = draw_eighth_note(canvas, size)
    return canvas


def save_sizes(base_img):
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    os.makedirs(ICON_DIR, exist_ok=True)
    for s in sizes:
        base_img.resize((s, s), Image.LANCZOS).save(
            os.path.join(ICON_DIR, f"icon_{s}x{s}.png")
        )
    print(f"Wrote {len(sizes)} PNGs to {ICON_DIR}")


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
    print("Wrote Contents.json")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    img = make_icon()
    save_sizes(img)
    write_contents_json()
    print("Done. Rebuild the Xcode project to pick up the new icon.")
