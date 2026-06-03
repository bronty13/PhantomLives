"""
Purple Tree app icon generator.

Renders a 1024x1024 master with a macOS Big Sur-style squircle background
(deep purple gradient matching the PhantomLives Purple* family) and a
stylized *treemap* motif — nested rounded rectangles of varying size, the
visual signature of a disk-space analyzer — with a soft top gloss.

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

# Brand palette (mirrors the Purple* family)
LAVENDER = (167, 139, 250)    # #A78BFA
DEEP_VIOLET = (76, 29, 149)   # #4C1D95


def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """macOS Big Sur app icon corner radius is ~22.5% of the icon edge."""
    r = int(size * radius_ratio)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
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


def treemap_motif(size: int) -> Image.Image:
    """A squarified-treemap arrangement of translucent white tiles.

    Hand-laid rectangles (in a 0..1 unit square) that read as a disk-usage
    treemap: one big block, a medium column, and a cluster of small tiles.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Inset the motif inside the squircle.
    inset = 0.20
    span = 1.0 - 2 * inset

    def rect(x, y, w, h):
        return (
            (inset + x * span) * size,
            (inset + y * span) * size,
            (inset + (x + w) * span) * size,
            (inset + (y + h) * span) * size,
        )

    # (x, y, w, h, alpha) tiles — a believable squarified layout.
    tiles = [
        (0.00, 0.00, 0.56, 0.62, 255),   # dominant block
        (0.58, 0.00, 0.42, 0.30, 235),   # top-right wide
        (0.58, 0.32, 0.42, 0.30, 205),   # right mid
        (0.00, 0.64, 0.27, 0.36, 220),   # bottom-left
        (0.29, 0.64, 0.27, 0.36, 185),   # bottom-mid
        (0.58, 0.64, 0.20, 0.36, 235),   # bottom-right tall
        (0.80, 0.64, 0.20, 0.17, 165),   # small
        (0.80, 0.83, 0.20, 0.17, 200),   # small
    ]
    gap = size * 0.012
    radius = size * 0.028
    for (x, y, w, h, a) in tiles:
        x0, y0, x1, y1 = rect(x, y, w, h)
        d.rounded_rectangle(
            (x0 + gap, y0 + gap, x1 - gap, y1 - gap),
            radius=radius,
            fill=(255, 255, 255, a),
        )
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
    bg = purple_gradient(size)
    bg.alpha_composite(top_highlight(size))

    motif = treemap_motif(size)
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
    print("Rendering Purple Tree icon master (1024x1024)...")
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
