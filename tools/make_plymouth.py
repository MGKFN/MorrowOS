#!/usr/bin/env python3
"""
Generate the MorrowOS "Dawn" Plymouth boot splash assets.

Same palette as the colour scheme, wallpaper and icons, so the boot splash
is the same identity as the desktop it fades into.

Everything the splash draws is a PNG generated here. That is deliberate:

  * Plymouth's script module has NO Rectangle() primitive. The pre-v1.2
    theme drew its background and progress bar with Rectangle(), which is
    an undefined function -- the script aborts and you get a blank or
    stock splash. Shapes must be images.
  * Image.Text() needs a font INSIDE the initrd. Which fonts the plymouth
    initramfs hook pulls in varies by release, so text that renders on the
    build host can silently vanish at boot. Pre-rendering the wordmark
    here removes that dependency completely.

The flat background is done with Window.SetBackgroundTopColor/BottomColor
in the script rather than a full-screen image, so it is resolution
independent -- only the glow, mark, wordmark and bar are bitmaps, and each
is scaled to the real screen at runtime.

Writes into usr/share/plymouth-morrowos/, which build.sh copies to
/usr/share/plymouth/themes/morrowos.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from dawn_palette import rgb, NIGHT, INDIGO, AMBER, CORAL, EMBER, TEXT, TEXT_DIM  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "usr" / "share" / "plymouth-morrowos"

# Reference canvas. The script scales these to the real mode at boot.
GLOW_W, GLOW_H = 1600, 520
MARK = 256
BAR_W, BAR_H = 420, 4

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
]
FONT_LIGHT = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
]


def load_font(candidates, size):
    for path in candidates:
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    raise SystemExit(
        "No usable TTF font found. Install fonts-dejavu-core "
        "(apt-get install -y fonts-dejavu-core) and re-run.\n"
        "Tried:\n  " + "\n  ".join(candidates))


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ── horizon glow ────────────────────────────────────────────────────────────
def make_glow() -> Image.Image:
    """
    The dawn itself: a wide, soft amber bloom on a horizon.

    Computed per-pixel rather than as stacked ellipses. Stacked ellipses
    band visibly at this size -- you can count the rings on a dark screen,
    which is exactly where a boot splash is looked at.

    Luminance becomes alpha, so the glow reads as light added to the
    window gradient instead of a shape pasted over it.
    """
    w, h = GLOW_W, GLOW_H
    cx, cy = w / 2, h * 0.5
    # deliberately flat: the light belongs to the horizon, not to a
    # blob behind the wordmark. A tall glow greys out the text under it.
    rx, ry = w * 0.42, h * 0.46

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    # normalised elliptical distance from the glow centre
    dist = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    fall = np.clip(1.0 - dist, 0.0, 1.0) ** 3.2

    warm = np.array(rgb(AMBER), dtype=np.float64)
    hot = np.array(rgb(CORAL), dtype=np.float64)
    # hotter in the core, cooler at the fringe
    mix = np.clip(dist ** 0.5, 0.0, 1.0)[..., None]
    colour = hot * (1.0 - mix) + warm * mix

    rgb_arr = (colour * fall[..., None] * 0.80).clip(0, 255)
    alpha = rgb_arr.max(axis=2)

    out = np.dstack([rgb_arr, alpha]).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    return img.filter(ImageFilter.GaussianBlur(radius=h * 0.04))


# ── sun-over-horizon mark ───────────────────────────────────────────────────
def make_mark() -> Image.Image:
    """
    The MorrowOS mark: a sun clearing a horizon line.

    Built as three separate layers -- bloom, disc, horizon rule -- and
    composited. The disc is masked to stop at the horizon so the sun rises
    out of the rule rather than having a line drawn across it, and the
    bloom is computed per-pixel so it reaches zero before the canvas edge.
    A bloom that is still non-zero at the boundary shows up as a bright
    rectangle on a dark screen.
    """
    ss = 4
    s = MARK * ss
    cx, cy = s / 2, s * 0.54
    r = s * 0.29
    hz_y = s * 0.68
    rule_h = max(int(s * 0.014), 1)

    yy, xx = np.mgrid[0:s, 0:s].astype(np.float64)
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    # bloom: zero by 92% of the half-canvas, so no edge artefact
    reach = s * 0.46
    bloom_f = np.clip(1.0 - dist / reach, 0.0, 1.0) ** 3.0 * 0.62
    warm = np.array(rgb(AMBER), dtype=np.float64)
    bloom_rgb = warm * bloom_f[..., None]
    bloom_a = bloom_rgb.max(axis=2)

    # disc: amber at the crown grading to coral at the base
    t = np.clip((yy - (cy - r)) / (2 * r), 0.0, 1.0)[..., None]
    disc_rgb = warm * (1.0 - t) + np.array(rgb(CORAL), dtype=np.float64) * t
    # antialiased edge, and cut flat at the horizon
    disc_a = np.clip((r - dist) * ss * 0.5, 0.0, 1.0) * 255.0
    disc_a = np.where(yy > hz_y, 0.0, disc_a)

    # horizon rule: brightest under the sun, fading out to both sides
    half = s * 0.43
    lat = np.clip(np.abs(xx - cx) / half, 0.0, 1.0)
    rule_a = np.where((yy >= hz_y) & (yy < hz_y + rule_h),
                      (1.0 - lat ** 1.7) * 255.0, 0.0)
    rule_rgb = np.broadcast_to(np.array(rgb(EMBER), dtype=np.float64), (s, s, 3))

    # composite: bloom, then rule, then disc on top
    out_rgb = bloom_rgb.copy()
    out_a = bloom_a.copy()
    for layer_rgb, layer_a in ((rule_rgb, rule_a), (disc_rgb, disc_a)):
        a = (layer_a / 255.0)[..., None]
        out_rgb = layer_rgb * a + out_rgb * (1 - a)
        out_a = layer_a + out_a * (1 - a[..., 0])

    arr = np.dstack([out_rgb.clip(0, 255), out_a.clip(0, 255)]).astype(np.uint8)
    return Image.fromarray(arr, "RGBA").resize((MARK, MARK), Image.LANCZOS)


# ── wordmark ────────────────────────────────────────────────────────────────
def make_wordmark() -> Image.Image:
    ss = 3
    font = load_font(FONT_CANDIDATES, 52 * ss)
    tag_font = load_font(FONT_LIGHT, 17 * ss)

    text, tag = "MorrowOS", "Built for tomorrow"
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    tb = probe.textbbox((0, 0), text, font=font)
    gb = probe.textbbox((0, 0), tag, font=tag_font)

    pad = 20 * ss
    gap = 16 * ss
    w = max(tb[2] - tb[0], gb[2] - gb[0]) + pad * 2
    h = (tb[3] - tb[1]) + gap + (gb[3] - gb[1]) + pad * 2

    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    x = w / 2
    d.text((x, pad - tb[1]), text, font=font, fill=rgb(TEXT) + (255,), anchor="ma")
    d.text((x, pad + (tb[3] - tb[1]) + gap - gb[1]), tag,
           font=tag_font, fill=rgb(TEXT_DIM) + (255,), anchor="ma")

    return img.resize((w // ss, h // ss), Image.LANCZOS)


# ── progress bar ────────────────────────────────────────────────────────────
def make_bar_track() -> Image.Image:
    img = Image.new("RGBA", (BAR_W, BAR_H), (0, 0, 0, 0))
    ImageDraw.Draw(img).rectangle([0, 0, BAR_W, BAR_H], fill=rgb(INDIGO) + (170,))
    return img


def make_bar_fill() -> Image.Image:
    """Amber-to-coral, so the leading edge is the warmest part of the bar."""
    img = Image.new("RGBA", (BAR_W, BAR_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    a, b = rgb(AMBER), rgb(CORAL)
    for x in range(BAR_W):
        d.line([(x, 0), (x, BAR_H)], fill=lerp(a, b, x / max(BAR_W - 1, 1)) + (255,))
    return img


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    assets = {
        "glow.png": make_glow(),
        "mark.png": make_mark(),
        "wordmark.png": make_wordmark(),
        "bar-track.png": make_bar_track(),
        "bar-fill.png": make_bar_fill(),
    }
    for name, img in assets.items():
        path = OUT / name
        img.save(path, "PNG", optimize=True)
        print(f"  {path.relative_to(OUT.parent.parent.parent.parent)}"
              f"  {img.size[0]}x{img.size[1]}  {path.stat().st_size:,} B")
    print(f"\nwrote {len(assets)} asset(s) to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
