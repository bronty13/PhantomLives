"""
Purple PDF app icon generator.

Renders a 1024x1024 master with a macOS Big Sur-style squircle background
(deep purple gradient matching PurpleTracker), a white document silhouette
with a folded top-right corner, a bold "PDF" wordmark on the document face,
and a subtle top gloss highlight.

Exports:
  - icon_master_1024.png  (the truth)
  - icon.icns             (all macOS sizes, via iconutil if available)
  - icon.ico              (16/32/48/64/128/256 Windows icon)
  - png/icon_<size>.png   (intermediate masters used to build .icns/.ico)
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
OUTDIR = HERE
PNG_DIR = HERE / "png"
PNG_DIR.mkdir(exist_ok=True)

MASTER = 1024

# Brand palette (mirrors PurpleTracker/Resources/make_icon.py)
LAVENDER = (167, 139, 250)    # #A78BFA
DEEP_VIOLET = (76, 29, 149)   # #4C1D95


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------
def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """macOS Big Sur app icon corner radius is ~22.5% of the icon edge."""
    r = int(size * radius_ratio)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=r, fill=255
    )
    return mask


def purple_gradient(size: int) -> Image.Image:
    """Diagonal lavender -> deep violet gradient."""
    img = Image.new("RGB", (size, size), LAVENDER)
    px = img.load()
    denom = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom
            r = int(LAVENDER[0] + (DEEP_VIOLET[0] - LAVENDER[0]) * t)
            g = int(LAVENDER[1] + (DEEP_VIOLET[1] - LAVENDER[1]) * t)
            b = int(LAVENDER[2] + (DEEP_VIOLET[2] - LAVENDER[2]) * t)
            px[x, y] = (r, g, b)
    return img.convert("RGBA")


def top_highlight(size: int) -> Image.Image:
    h = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(h).ellipse(
        (-size * 0.2, -size * 0.55, size * 1.2, size * 0.45),
        fill=(255, 255, 255, 55),
    )
    return h.filter(ImageFilter.GaussianBlur(radius=size * 0.06))


def find_font(size_px: int) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size_px)
            except OSError:
                continue
    return ImageFont.load_default()


# ---------------------------------------------------------------------------
# Document silhouette with folded corner
# ---------------------------------------------------------------------------
def document_shape(size: int) -> Image.Image:
    """White page with a folded top-right corner.

    Returned image is RGBA the same size as the canvas, with the page
    positioned slightly off-center to allow room for a soft drop shadow.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Page bounds (centered, slight upward bias for visual weight)
    pad_x = int(size * 0.20)
    pad_top = int(size * 0.16)
    pad_bot = int(size * 0.12)
    left = pad_x
    right = size - pad_x
    top = pad_top
    bottom = size - pad_bot

    fold = int(size * 0.16)  # how big the folded corner is

    page_white = (255, 255, 255, 255)
    fold_shadow = (220, 210, 245, 255)   # subtle purple-tinted page back
    fold_face = (240, 235, 252, 255)     # the folded-over corner face

    # Main page polygon: rectangle with the top-right corner clipped
    page_poly = [
        (left, top),
        (right - fold, top),
        (right, top + fold),
        (right, bottom),
        (left, bottom),
    ]
    d.polygon(page_poly, fill=page_white)

    # Folded-corner triangle (lighter, suggests the back of the folded paper)
    fold_poly = [
        (right - fold, top),
        (right, top + fold),
        (right - fold, top + fold),
    ]
    # Slight inner shadow at the fold crease
    d.polygon(fold_poly, fill=fold_face)
    d.line(
        [(right - fold, top), (right - fold, top + fold), (right, top + fold)],
        fill=fold_shadow,
        width=max(2, size // 256),
    )

    return img, (left, top, right, bottom, fold)


def draw_pdf_wordmark(canvas: Image.Image, page_bounds, size: int) -> None:
    left, top, right, bottom, fold = page_bounds
    page_w = right - left
    page_h = bottom - top

    # Stack: "PDF" centered, sized to fill the page generously
    text = "PDF"
    target_w = int(page_w * 0.78)

    # Binary-search a font size that fits
    lo, hi = 10, int(page_h * 0.7)
    best = lo
    while lo <= hi:
        mid = (lo + hi) // 2
        f = find_font(mid)
        bbox = f.getbbox(text)
        w = bbox[2] - bbox[0]
        if w <= target_w:
            best = mid
            lo = mid + 1
        else:
            hi = mid - 1
    font = find_font(best)

    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    # Center horizontally; vertically a touch above middle (looks balanced
    # with the folded corner)
    cx = left + (page_w - tw) // 2 - bbox[0]
    cy = top + (page_h - th) // 2 - bbox[1] - int(size * 0.01)

    d = ImageDraw.Draw(canvas)
    # Brand purple text on white page reads as a wordmark, not a label
    d.text((cx, cy), text, font=font, fill=DEEP_VIOLET)


def soft_drop_shadow(shape: Image.Image, size: int) -> Image.Image:
    """Generate a soft shadow image from an RGBA shape's alpha."""
    alpha = shape.split()[-1]
    shadow = Image.new("RGBA", shape.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda v: int(v * 0.35)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=size * 0.018))
    # Offset down slightly
    offset = Image.new("RGBA", shape.size, (0, 0, 0, 0))
    offset.paste(shadow, (0, int(size * 0.012)), shadow)
    return offset


# ---------------------------------------------------------------------------
# Compose
# ---------------------------------------------------------------------------
def render_master(size: int = MASTER) -> Image.Image:
    bg = purple_gradient(size)
    bg.alpha_composite(top_highlight(size))

    doc, bounds = document_shape(size)
    draw_pdf_wordmark(doc, bounds, size)

    shadow = soft_drop_shadow(doc, size)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(bg)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(doc)

    # Apply squircle mask for macOS-style rounding
    mask = squircle_mask(size)
    rounded = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rounded.paste(canvas, (0, 0), mask)
    return rounded


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_SIZES = [16, 32, 48, 64, 128, 256]


def export_pngs(master: Image.Image) -> dict[int, Path]:
    paths: dict[int, Path] = {}
    for s in sorted(set(ICNS_SIZES + ICO_SIZES + [MASTER])):
        out = PNG_DIR / f"icon_{s}.png"
        img = master.resize((s, s), Image.LANCZOS)
        img.save(out, "PNG")
        paths[s] = out
    return paths


def export_icns(pngs: dict[int, Path]) -> Path | None:
    """Build icon.icns via macOS `iconutil` if available."""
    iconutil = shutil.which("iconutil")
    icns_path = OUTDIR / "icon.icns"
    if not iconutil:
        # Fallback: let Pillow write a multi-resolution .icns directly.
        try:
            sizes = [(s, s) for s in [16, 32, 64, 128, 256, 512, 1024] if s in pngs]
            base = Image.open(pngs[1024])
            base.save(icns_path, format="ICNS", sizes=sizes)
            return icns_path
        except Exception as e:
            print(f"  (skipping .icns: {e})", file=sys.stderr)
            return None

    iconset = OUTDIR / "icon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    pairs = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in pairs:
        shutil.copy(pngs[size], iconset / name)
    subprocess.run(
        [iconutil, "-c", "icns", str(iconset), "-o", str(icns_path)],
        check=True,
    )
    shutil.rmtree(iconset)
    return icns_path


def export_ico(pngs: dict[int, Path]) -> Path:
    ico_path = OUTDIR / "icon.ico"
    base = Image.open(pngs[256])
    sizes = [(s, s) for s in ICO_SIZES]
    base.save(ico_path, format="ICO", sizes=sizes)
    return ico_path


def main() -> int:
    print("Rendering Purple PDF icon master (1024x1024)...")
    master = render_master(MASTER)
    master_path = OUTDIR / "icon_master_1024.png"
    master.save(master_path, "PNG")
    print(f"  wrote {master_path}")

    print("Exporting PNG sizes...")
    pngs = export_pngs(master)
    for s, p in sorted(pngs.items()):
        print(f"  {s:4d}px -> {p.name}")

    print("Building icon.icns ...")
    icns = export_icns(pngs)
    if icns:
        print(f"  wrote {icns}")

    print("Building icon.ico ...")
    ico = export_ico(pngs)
    print(f"  wrote {ico}")

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
