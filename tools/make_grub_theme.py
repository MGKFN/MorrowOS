#!/usr/bin/env python3
"""
Generate the MorrowOS "Dawn" GRUB boot-menu theme assets.

The GRUB menu is the first MorrowOS screen anyone sees -- before Plymouth,
before SDDM -- and through v1.2 it was stock white-on-black text.

Unlike the Plymouth splash this touches nothing in the initrd: the theme is
plain files in the ISO tree. If GRUB cannot load it (no gfxmenu, no png
module, a malformed theme.txt) it falls back to the text menu and still
boots. That is why this and the splash are separate steps.

Writes into iso/grub-theme/, which build.sh copies to
/boot/grub/themes/morrowos on the ISO.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from dawn_palette import rgb, NIGHT, INDIGO, AMBER, CORAL, EMBER  # noqa: E402
from make_plymouth import make_wordmark  # noqa: E402  (one wordmark, one source)

OUT = Path(__file__).resolve().parent.parent / "iso" / "grub-theme"
W, H = 1920, 1080
SLICE = 16          # 9-slice tile size for the selection highlight


def make_background() -> Image.Image:
    """
    Dawn, composed for a menu rather than for a splash.

    The glow sits low and the top two thirds stay flat and dark, because
    the menu items are drawn over the middle of this and have to stay
    readable. Same reasoning as the wallpaper.
    """
    top, mid = np.array(rgb(NIGHT), float), np.array(rgb(INDIGO), float)
    t = (np.arange(H) / (H - 1)) ** 1.6
    base = (top + (mid - top) * t[:, None, None]).repeat(W, axis=1)

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    cx, cy = W / 2, H * 1.02
    rx, ry = W * 0.55, H * 0.46
    dist = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    fall = np.clip(1.0 - dist, 0.0, 1.0) ** 2.8

    mix = np.clip(dist ** 0.6, 0.0, 1.0)[..., None]
    colour = np.array(rgb(CORAL), float) * (1 - mix) + np.array(rgb(AMBER), float) * mix
    out = np.clip(base + colour * fall[..., None] * 0.55, 0, 255)

    # a thin ember horizon rule, fading out to both sides
    hz = int(H * 0.70)
    lat = np.clip(np.abs(np.arange(W) - W / 2) / (W * 0.44), 0, 1)
    strength = (1.0 - lat ** 1.8) * 0.5
    for dy in range(2):
        row = out[hz + dy]
        out[hz + dy] = np.clip(
            row + np.array(rgb(EMBER), float) * strength[:, None], 0, 255)

    return Image.fromarray(out.astype("uint8"), "RGB")


def make_selection_slices():
    """
    Nine-slice pixmap for the highlighted menu row.

    GRUB composes `selected_item_pixmap_style` from <name>_c/_n/_s/_e/_w
    and the four corners, so a rounded amber bar costs nine small files
    and looks far better than a bare colour change.
    """
    amber = rgb(AMBER) + (235,)
    s = SLICE

    corner = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(corner).pieslice([0, 0, s * 2, s * 2], 180, 270, fill=amber)

    solid_h = Image.new("RGBA", (s, s), amber)

    return {
        "select_nw.png": corner,
        "select_ne.png": corner.transpose(Image.FLIP_LEFT_RIGHT),
        "select_sw.png": corner.transpose(Image.FLIP_TOP_BOTTOM),
        "select_se.png": corner.transpose(Image.ROTATE_180),
        "select_n.png": solid_h,
        "select_s.png": solid_h,
        "select_e.png": solid_h,
        "select_w.png": solid_h,
        "select_c.png": solid_h,
    }


def make_progress_slices():
    """Timeout countdown bar: a dim indigo trough with an amber fill."""
    trough = Image.new("RGBA", (SLICE, SLICE), rgb(INDIGO) + (190,))
    fill = Image.new("RGBA", (SLICE, SLICE), rgb(AMBER) + (255,))
    out = {}
    for tag, img in (("bar", trough), ("hl", fill)):
        for part in ("c", "n", "s", "e", "w", "nw", "ne", "sw", "se"):
            out[f"progress_{tag}_{part}.png"] = img
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    assets = {"background.png": make_background(),
              "wordmark.png": make_wordmark()}
    assets.update(make_selection_slices())
    assets.update(make_progress_slices())

    for name, img in sorted(assets.items()):
        img.save(OUT / name, "PNG", optimize=True)

    total = sum((OUT / n).stat().st_size for n in assets)
    print(f"  background.png  {W}x{H}  "
          f"{(OUT / 'background.png').stat().st_size:,} B")
    wm = assets["wordmark.png"]
    print(f"  wordmark.png    {wm.size[0]}x{wm.size[1]}  "
          f"{(OUT / 'wordmark.png').stat().st_size:,} B")
    print(f"  + {len(assets) - 2} nine-slice tiles")
    print(f"\nwrote {len(assets)} file(s), {total:,} B total to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
