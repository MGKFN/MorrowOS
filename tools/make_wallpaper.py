#!/usr/bin/env python3
"""
Generate the MorrowOS "Dawn" wallpaper.

A sunrise over layered ridges, built from the same palette as the colour
scheme and icons. Deliberately dark and low-contrast in the upper two
thirds so desktop icons and panel text stay readable on top of it; the
warmth is concentrated near the horizon, low and to the centre where
windows usually aren't.

Renders at 2x and downsamples, so the gradients and ridge edges come out
smooth without needing any antialiasing tricks.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
from dawn_palette import rgb, NIGHT, INDIGO, AMBER, CORAL, EMBER  # noqa: E402

W, H = 1920, 1080
SS = 2                      # supersample factor
HORIZON = 0.66              # fraction of height where the ridges start
SUN_X, SUN_Y, SUN_R = 0.50, 0.655, 0.115


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky(w: int, h: int) -> Image.Image:
    """Vertical gradient: deep night at the top easing into ember at the horizon."""
    top, mid, low = rgb(NIGHT), rgb(INDIGO), rgb(EMBER)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    hz = int(h * HORIZON)
    for y in range(h):
        if y < hz:
            t = y / max(hz, 1)
            # ease-in so the top two-thirds stay dark and flat
            t = t ** 2.4
            c = lerp(top, mid, min(t * 2.0, 1.0))
            if t > 0.5:
                c = lerp(c, low, (t - 0.5) / 0.5 * 0.55)
        else:
            t = (y - hz) / max(h - hz, 1)
            c = lerp(lerp(rgb(INDIGO), low, 0.55), rgb(NIGHT), t ** 0.6)
        d.line([(0, y), (w, y)], fill=c)
    return img


def glow(img: Image.Image, w: int, h: int) -> Image.Image:
    """Radial sun glow, added rather than pasted so it blooms into the sky."""
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = w * SUN_X, h * SUN_Y
    rmax = h * 0.62
    steps = 90
    warm = rgb(AMBER)
    for i in range(steps, 0, -1):
        t = i / steps
        r = rmax * t
        # falls off fast, so the glow stays local to the horizon
        a = (1.0 - t) ** 3.1 * 0.55
        c = tuple(round(warm[j] * a) for j in range(3))
        d.ellipse([cx - r, cy - r * 0.62, cx + r, cy + r * 0.62], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=h * 0.045))
    return Image.blend(img, Image.new("RGB", (w, h), (0, 0, 0)), 0.0) \
        .point(lambda v: v) if False else _add(img, layer)


def _add(a: Image.Image, b: Image.Image) -> Image.Image:
    from PIL import ImageChops
    return ImageChops.add(a, b)


def sun(img: Image.Image, w: int, h: int) -> Image.Image:
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy, r = w * SUN_X, h * SUN_Y, h * SUN_R
    steps = 60
    for i in range(steps):
        t = i / steps
        rr = r * (1 - t)
        c = lerp(rgb(CORAL), rgb(AMBER), t)
        c = tuple(round(v * 0.92) for v in c)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=c)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=h * 0.006))
    return _add(img, layer)


def ridge(img: Image.Image, w: int, h: int, *, base: float, amp: float,
          freq: float, phase: float, colour, alpha: float) -> Image.Image:
    """One silhouetted ridge line, composited at the given opacity."""
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    mask = Image.new("L", (w, h), 0)
    ld, md = ImageDraw.Draw(layer), ImageDraw.Draw(mask)
    pts = []
    for x in range(0, w + 1, 4):
        u = x / w
        y = base * h + math.sin(u * freq * math.tau + phase) * amp * h \
            + math.sin(u * freq * 2.7 * math.tau + phase * 1.7) * amp * 0.35 * h
        pts.append((x, y))
    poly = pts + [(w, h), (0, h)]
    ld.polygon(poly, fill=colour)
    md.polygon(poly, fill=round(255 * alpha))
    return Image.composite(layer, img, mask)


def build() -> Image.Image:
    w, h = W * SS, H * SS
    img = sky(w, h)
    img = glow(img, w, h)
    img = sun(img, w, h)

    # Ridges from far (light, hazy) to near (almost black), so the horizon
    # has depth and the bottom of the screen is dark enough for a panel.
    far = lerp(rgb(EMBER), rgb(NIGHT), 0.45)
    mid = lerp(rgb(INDIGO), rgb(NIGHT), 0.35)
    near = rgb(NIGHT)
    img = ridge(img, w, h, base=0.700, amp=0.022, freq=1.3, phase=0.4,
                colour=far,  alpha=0.85)
    img = ridge(img, w, h, base=0.780, amp=0.030, freq=0.9, phase=2.1,
                colour=mid,  alpha=0.92)
    img = ridge(img, w, h, base=0.880, amp=0.026, freq=1.7, phase=4.3,
                colour=near, alpha=1.0)

    return img.resize((W, H), Image.LANCZOS)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    out = root / "usr/share/wallpapers/MorrowOS/contents/images"
    out.mkdir(parents=True, exist_ok=True)
    img = build()
    img.save(out / "1920x1080.png")
    img.save(out / "1920x1080.jpg", quality=92)
    print(f"wrote {(out / '1920x1080.png').relative_to(root)}")
    print(f"wrote {(out / '1920x1080.jpg').relative_to(root)}")

    # KDE's wallpaper picker shows contents/screenshot.png; without it the
    # entry appears as a blank tile.
    shot = out.parent / "screenshot.png"
    img.resize((960, 540), Image.LANCZOS).save(shot)
    print(f"wrote {shot.relative_to(root)}")
