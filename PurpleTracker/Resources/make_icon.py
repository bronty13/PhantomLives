"""
PurpleTracker app icon generator.

Renders a 1024×1024 master with a macOS Big Sur–style squircle background
(deep purple gradient), a chunky "PT" monogram in white, and a small accent
dot evoking the Matter ID tag. Then exports all sizes the AppIcon set wants.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os, math

MASTER = 1024
OUTDIR = os.path.expanduser(
    "~/Documents/GitHub/PhantomLives/PurpleTracker/Sources/PurpleTracker/"
    "Resources/Assets.xcassets/AppIcon.appiconset"
)

# --- Squircle (rounded-rect, macOS-style) ---------------------------------
def squircle_mask(size, radius_ratio=0.225):
    """macOS Big Sur app icon corner radius is ~22.5% of the icon edge."""
    r = int(size * radius_ratio)
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask

# --- Diagonal purple gradient --------------------------------------------
def purple_gradient(size):
    top    = (167, 139, 250)   # #A78BFA - lavender
    bottom = ( 76,  29, 149)   # #4C1D95 - deep violet
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        for x in range(size):
            # diagonal blend (top-left → bottom-right)
            t = (x + y) / (2 * (size - 1))
            r = int(top[0] + (bottom[0] - top[0]) * t)
            g = int(top[1] + (bottom[1] - top[1]) * t)
            b = int(top[2] + (bottom[2] - top[2]) * t)
            px[x, y] = (r, g, b)
    return img.convert("RGBA")

# --- Subtle top highlight (gloss) ----------------------------------------
def top_highlight(size):
    h = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(h)
    # soft white ellipse near the top, blurred
    d.ellipse((-size * 0.2, -size * 0.55, size * 1.2, size * 0.45),
              fill=(255, 255, 255, 55))
    return h.filter(ImageFilter.GaussianBlur(radius=size * 0.06))

# --- PT monogram ---------------------------------------------------------
def find_font(size_px):
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size_px)
            except OSError:
                continue
    return ImageFont.load_default()

def render_master():
    size = MASTER
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 1. Gradient body, clipped to squircle
    grad = purple_gradient(size)
    mask = squircle_mask(size)
    base.paste(grad, (0, 0), mask)

    # 2. Soft top highlight, also clipped
    hl = top_highlight(size)
    hl_clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_clipped.paste(hl, (0, 0), mask)
    base = Image.alpha_composite(base, hl_clipped)

    # 3. PT monogram in white
    text = "PT"
    font = find_font(int(size * 0.62))
    # measure
    tmp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    td = ImageDraw.Draw(tmp)
    bbox = td.textbbox((0, 0), text, font=font, stroke_width=0)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (size - tw) // 2 - bbox[0]
    ty = (size - th) // 2 - bbox[1] - int(size * 0.02)  # nudge up optically

    # subtle drop shadow for depth
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.text((tx + int(size*0.012), ty + int(size*0.018)),
            text, font=font, fill=(40, 10, 80, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=size * 0.012))
    base = Image.alpha_composite(base, shadow)

    td2 = ImageDraw.Draw(base)
    td2.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))

    # 4. Accent dot — small white-bordered circle in upper right,
    #    suggesting a "tag" / matter-number marker.
    dot_d = int(size * 0.10)
    dot_x = int(size * 0.74)
    dot_y = int(size * 0.16)
    od = ImageDraw.Draw(base)
    # outer ring
    od.ellipse((dot_x, dot_y, dot_x + dot_d, dot_y + dot_d),
               fill=(255, 255, 255, 255))
    # inner purple disc
    pad = int(dot_d * 0.22)
    od.ellipse((dot_x + pad, dot_y + pad,
                dot_x + dot_d - pad, dot_y + dot_d - pad),
               fill=(91, 33, 182, 255))
    # inner highlight
    sh = int(dot_d * 0.14)
    od.ellipse((dot_x + pad + sh, dot_y + pad + sh,
                dot_x + pad + sh + int(dot_d*0.18),
                dot_y + pad + sh + int(dot_d*0.18)),
               fill=(255, 255, 255, 160))

    # 5. Faint outer rim shadow (very subtle)
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.rounded_rectangle((0, 0, size - 1, size - 1),
                         radius=int(size * 0.225),
                         outline=(0, 0, 0, 40),
                         width=int(size * 0.004))
    base = Image.alpha_composite(base, rim)

    return base

# --- Export sizes for the AppIcon.appiconset -----------------------------
# (size, scale, filename)
SIZES = [
    (16,  1, "icon_16x16.png"),
    (32,  2, "icon_16x16@2x.png"),
    (32,  1, "icon_32x32.png"),
    (64,  2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (256, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (512, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (1024,2, "icon_512x512@2x.png"),
]

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    master = render_master()
    master.save(os.path.join(OUTDIR, "_master_1024.png"))
    for px, _, fname in SIZES:
        out = master.resize((px, px), Image.LANCZOS)
        out.save(os.path.join(OUTDIR, fname))
        print(f"✓ {fname} ({px}×{px})")
    # Update Contents.json with filenames
    import json
    contents = {
        "images": [
            {"idiom":"mac","scale":"1x","size":"16x16","filename":"icon_16x16.png"},
            {"idiom":"mac","scale":"2x","size":"16x16","filename":"icon_16x16@2x.png"},
            {"idiom":"mac","scale":"1x","size":"32x32","filename":"icon_32x32.png"},
            {"idiom":"mac","scale":"2x","size":"32x32","filename":"icon_32x32@2x.png"},
            {"idiom":"mac","scale":"1x","size":"128x128","filename":"icon_128x128.png"},
            {"idiom":"mac","scale":"2x","size":"128x128","filename":"icon_128x128@2x.png"},
            {"idiom":"mac","scale":"1x","size":"256x256","filename":"icon_256x256.png"},
            {"idiom":"mac","scale":"2x","size":"256x256","filename":"icon_256x256@2x.png"},
            {"idiom":"mac","scale":"1x","size":"512x512","filename":"icon_512x512.png"},
            {"idiom":"mac","scale":"2x","size":"512x512","filename":"icon_512x512@2x.png"},
        ],
        "info": {"author":"xcode","version":1}
    }
    with open(os.path.join(OUTDIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print(f"✓ Wrote Contents.json")

if __name__ == "__main__":
    main()
