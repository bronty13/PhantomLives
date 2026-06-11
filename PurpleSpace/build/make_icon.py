"""
Purple Space app icon generator.

Renders a 1024x1024 master with a macOS Big Sur-style squircle background
(deep iris gradient, a shade deeper than the rest of the PhantomLives
Purple* family) and a stylized *page* motif — a paper sheet carrying text
blocks and a small table grid, the visual signature of a block-based
workspace — with a soft top gloss.

Exports:
  - icon_master_1024.png  (the truth)
  - icon.icns             (all macOS sizes, via iconutil if available)
  - icon.ico              (16/32/48/64/128/256 Windows icon)
  - png/icon_<size>.png   (intermediate masters used to build .icns/.ico)
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
OUTDIR = HERE
PNG_DIR = HERE / "png"
PNG_DIR.mkdir(exist_ok=True)

MASTER = 1024

# Brand palette — deeper iris than PurpleTree's lavender, same family.
HELIOTROPE = (155, 123, 232)   # #9B7BE8
DEEP_IRIS = (59, 29, 122)      # #3B1D7A
PAPER = (250, 248, 243)        # warm paper, matches the app's light theme
INK = (84, 58, 153)            # text-block ink on the paper


def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """macOS Big Sur app icon corner radius is ~22.5% of the icon edge."""
    r = int(size * radius_ratio)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask


def iris_gradient(size: int) -> Image.Image:
    """Diagonal heliotrope -> deep iris gradient."""
    img = Image.new("RGB", (size, size), HELIOTROPE)
    px = img.load()
    denom = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom
            r = int(HELIOTROPE[0] + (DEEP_IRIS[0] - HELIOTROPE[0]) * t)
            g = int(HELIOTROPE[1] + (DEEP_IRIS[1] - HELIOTROPE[1]) * t)
            b = int(HELIOTROPE[2] + (DEEP_IRIS[2] - HELIOTROPE[2]) * t)
            px[x, y] = (r, g, b)
    return img.convert("RGBA")


def top_highlight(size: int) -> Image.Image:
    h = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(h).ellipse(
        (-size * 0.2, -size * 0.55, size * 1.2, size * 0.45),
        fill=(255, 255, 255, 55),
    )
    return h.filter(ImageFilter.GaussianBlur(radius=size * 0.06))


def page_motif(size: int) -> Image.Image:
    """A paper page carrying Notion-style content blocks.

    Top: a wide heading bar and shorter text lines. Bottom: a 3x2 table
    grid. The dog-eared corner sells "page" at every icon size.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Page bounds inside the squircle (portrait sheet, centered).
    px0, py0 = size * 0.26, size * 0.16
    px1, py1 = size * 0.74, size * 0.84
    radius = size * 0.035
    ear = (px1 - px0) * 0.26  # dog-ear edge length

    # Page body with a folded top-right corner: rounded rect minus the
    # ear triangle, then the fold drawn as a darker flap.
    page = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pd = ImageDraw.Draw(page)
    pd.rounded_rectangle((px0, py0, px1, py1), radius=radius, fill=PAPER + (255,))
    pd.polygon([(px1 - ear, py0 - 2), (px1 + 2, py0 - 2), (px1 + 2, py0 + ear)],
               fill=(0, 0, 0, 0))
    img.alpha_composite(page)
    # The fold flap.
    d.polygon([(px1 - ear, py0), (px1 - ear, py0 + ear), (px1, py0 + ear)],
              fill=(222, 215, 238, 255))

    # Content metrics.
    inset = (px1 - px0) * 0.14
    cx0, cx1 = px0 + inset, px1 - inset
    cw = cx1 - cx0
    bar_r = size * 0.012

    def line(y, w_frac, h, alpha=255, color=INK):
        d.rounded_rectangle((cx0, y, cx0 + cw * w_frac, y + h),
                            radius=bar_r, fill=color + (alpha,))

    lh = size * 0.030      # text line height
    heading_h = size * 0.052

    y = py0 + (px1 - px0) * 0.16
    line(y, 0.62, heading_h, 255)                 # heading block
    y += heading_h + size * 0.038
    line(y, 1.00, lh, 120)                        # body lines
    y += lh + size * 0.026
    line(y, 0.86, lh, 120)
    y += lh + size * 0.026
    line(y, 0.94, lh, 120)

    # Table grid block: 3 columns x 2 rows of light cells.
    ty0 = y + lh + size * 0.044
    ty1 = py1 - (px1 - px0) * 0.14
    cols, rows = 3, 2
    gap = size * 0.012
    cell_w = (cw - gap * (cols - 1)) / cols
    cell_h = (ty1 - ty0 - gap * (rows - 1)) / rows
    for r in range(rows):
        for c in range(cols):
            x0 = cx0 + c * (cell_w + gap)
            y0 = ty0 + r * (cell_h + gap)
            alpha = 255 if (r == 0 and c == 0) else 90
            fill = (HELIOTROPE + (alpha,)) if (r == 0 and c == 0) else (INK + (alpha,))
            d.rounded_rectangle((x0, y0, x0 + cell_w, y0 + cell_h),
                                radius=bar_r, fill=fill)
    return img


def soft_drop_shadow(shape: Image.Image, size: int) -> Image.Image:
    alpha = shape.split()[-1]
    shadow = Image.new("RGBA", shape.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda v: int(v * 0.30)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=size * 0.016))
    offset = Image.new("RGBA", shape.size, (0, 0, 0, 0))
    offset.paste(shadow, (0, int(size * 0.012)), shadow)
    return offset


def render_master(size: int = MASTER) -> Image.Image:
    bg = iris_gradient(size)
    bg.alpha_composite(top_highlight(size))

    motif = page_motif(size)
    shadow = soft_drop_shadow(motif, size)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(bg)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(motif)

    mask = squircle_mask(size)
    rounded = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rounded.paste(canvas, (0, 0), mask)
    return rounded


ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ICO_SIZES = [16, 32, 48, 64, 128, 256]


def export_pngs(master: Image.Image) -> dict[int, Path]:
    paths: dict[int, Path] = {}
    for s in sorted(set(ICNS_SIZES + ICO_SIZES + [MASTER])):
        out = PNG_DIR / f"icon_{s}.png"
        master.resize((s, s), Image.LANCZOS).save(out, "PNG")
        paths[s] = out
    return paths


def export_icns(pngs: dict[int, Path]) -> Path | None:
    iconutil = shutil.which("iconutil")
    icns_path = OUTDIR / "icon.icns"
    if not iconutil:
        try:
            sizes = [(s, s) for s in ICNS_SIZES if s in pngs]
            Image.open(pngs[1024]).save(icns_path, format="ICNS", sizes=sizes)
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
    subprocess.run([iconutil, "-c", "icns", str(iconset), "-o", str(icns_path)], check=True)
    shutil.rmtree(iconset)
    return icns_path


def export_ico(pngs: dict[int, Path]) -> Path:
    ico_path = OUTDIR / "icon.ico"
    Image.open(pngs[256]).save(ico_path, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    return ico_path


def main() -> int:
    print("Rendering Purple Space icon master (1024x1024)...")
    master = render_master(MASTER)
    master_path = OUTDIR / "icon_master_1024.png"
    master.save(master_path, "PNG")
    print(f"  wrote {master_path}")

    print("Exporting PNG sizes...")
    pngs = export_pngs(master)

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
