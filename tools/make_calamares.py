#!/usr/bin/env python3
"""
Generate the MorrowOS "Dawn" Calamares installer branding images.

Same palette as everything else, so the installer does not look like a
different product bolted onto the live session.

Calamares wants a handful of fixed-purpose images:
  logo.png       square product mark, shown in the sidebar
  welcome.png    banner on the first page
  slide-*.png    slideshow frames shown during the file copy

The slideshow is the only part of installer branding that can fail loudly
(a QML error), so the frames are plain images with the text baked in
rather than QML-drawn text -- there is nothing in them to go wrong.

Writes into etc/calamares/branding/morrowos/.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from dawn_palette import rgb, NIGHT, INDIGO, AMBER, CORAL, EMBER, TEXT, TEXT_DIM  # noqa: E402
from make_plymouth import make_mark, load_font, FONT_CANDIDATES, FONT_LIGHT  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "etc" / "calamares" / "branding" / "morrowos"
SLIDE_W, SLIDE_H = 900, 380


def dawn_panel(w: int, h: int, glow_y: float = 0.86) -> Image.Image:
    """The shared backdrop: night at the top, a warm bloom low down."""
    top, mid = np.array(rgb(NIGHT), float), np.array(rgb(INDIGO), float)
    t = (np.arange(h) / max(h - 1, 1)) ** 1.5
    base = (top + (mid - top) * t[:, None, None]).repeat(w, axis=1)

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    cx, cy = w / 2, h * glow_y
    rx, ry = w * 0.55, h * 0.40
    dist = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    fall = np.clip(1.0 - dist, 0.0, 1.0) ** 2.9

    mix = np.clip(dist ** 0.6, 0.0, 1.0)[..., None]
    colour = np.array(rgb(CORAL), float) * (1 - mix) + np.array(rgb(AMBER), float) * mix
    out = np.clip(base + colour * fall[..., None] * 0.50, 0, 255)
    return Image.fromarray(out.astype("uint8"), "RGB")


def make_logo(size: int = 256) -> Image.Image:
    """Reuse the boot mark so the installer and the splash are the same sun."""
    mark = make_mark()
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    m = mark.resize((size, size), Image.LANCZOS)
    img.alpha_composite(m)
    return img


def make_welcome(w: int = 900, h: int = 220) -> Image.Image:
    img = dawn_panel(w, h, glow_y=1.0).convert("RGBA")
    # The mark's lower half is transparent by design (the sun rises out of a
    # horizon), so it needs to sit high rather than optically centred.
    mark = make_mark().resize((140, 140), Image.LANCZOS)
    img.alpha_composite(mark, (44, (h - 140) // 2 - 14))

    d = ImageDraw.Draw(img)
    d.text((190, h / 2 - 22), "MorrowOS",
           font=load_font(FONT_CANDIDATES, 40), fill=rgb(TEXT) + (255,), anchor="lm")
    d.text((192, h / 2 + 20), "Built for tomorrow",
           font=load_font(FONT_LIGHT, 17), fill=rgb(TEXT_DIM) + (255,), anchor="lm")
    return img


SLIDES = [
    ("Welcome to MorrowOS",
     "A KDE Plasma desktop with its own identity,\nbuilt on a stable Ubuntu base."),
    ("Everything ready to go",
     "Firefox, LibreOffice and VLC are installed.\nMorrowStore adds thousands more."),
    ("Yours to change",
     "The Dawn theme, icons and wallpapers are all\ngenerated from one palette file."),
    ("Nearly there",
     "MorrowOS is being copied to your disk.\nThis takes a few minutes."),
]


def make_slide(title: str, body: str) -> Image.Image:
    img = dawn_panel(SLIDE_W, SLIDE_H).convert("RGBA")
    mark = make_mark().resize((104, 104), Image.LANCZOS)
    img.alpha_composite(mark, (SLIDE_W // 2 - 52, 58))

    # No separate rule under the mark: the mark already carries a horizon, and
    # a second horizontal line next to it reads as an underline, not as part
    # of the logo.
    d = ImageDraw.Draw(img)
    d.text((SLIDE_W / 2, 186), title,
           font=load_font(FONT_CANDIDATES, 34), fill=rgb(TEXT) + (255,), anchor="ma")
    d.multiline_text((SLIDE_W / 2, 248), body, font=load_font(FONT_LIGHT, 19),
                     fill=rgb(TEXT_DIM) + (255,), anchor="ma", align="center", spacing=11)
    return img


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    assets = {"logo.png": make_logo(), "welcome.png": make_welcome()}
    for i, (title, body) in enumerate(SLIDES, 1):
        assets[f"slide-{i}.png"] = make_slide(title, body)

    for name, img in assets.items():
        img.save(OUT / name, "PNG", optimize=True)
        print(f"  {name:<16} {img.size[0]}x{img.size[1]}  {(OUT / name).stat().st_size:,} B")
    print(f"\nwrote {len(assets)} file(s) to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
