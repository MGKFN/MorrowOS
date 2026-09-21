#!/usr/bin/env python3
"""
Rasterise the MorrowOS SVG marks into a hicolor icon tree.

Small sizes get a simplified variant: the rays in the bare logo turn to mush
below ~32px, so they're stripped from the source before rendering at those
sizes rather than rendered and hoped for.

Output: usr/share/icons/hicolor/<size>x<size>/apps/<name>.png
        plus the 256px PNG at usr/share/icons/<name>.png for build.sh.
"""
import re
import sys
from pathlib import Path

import cairosvg

SIZES = [16, 22, 24, 32, 48, 64, 128, 256]
DROP_RAYS_BELOW = 32

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "usr/share/icons"
HICOLOR = ICONS / "hicolor"

# name -> whether it has a <g class="rays"> group to strip at small sizes
MARKS = {
    "morrowos-logo": True,
    "morrowstore": False,
}

RAYS_RE = re.compile(r'<g class="rays".*?</g>', re.DOTALL)


def render(svg_text: str, size: int, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(
        bytestring=svg_text.encode(),
        write_to=str(out),
        output_width=size,
        output_height=size,
    )


def main() -> int:
    for name, has_rays in MARKS.items():
        src = ICONS / f"{name}.svg"
        if not src.exists():
            print(f"MISSING SOURCE: {src}", file=sys.stderr)
            return 1
        full = src.read_text()
        simple = RAYS_RE.sub("", full) if has_rays else full

        for size in SIZES:
            text = simple if (has_rays and size < DROP_RAYS_BELOW) else full
            out = HICOLOR / f"{size}x{size}" / "apps" / f"{name}.png"
            render(text, size, out)
        # flat copy at 256 for the pixmaps fallback
        render(full, 256, ICONS / f"{name}.png")
        print(f"{name}: {len(SIZES)} sizes + 256px flat copy")

    # index.theme is required or the hicolor tree is ignored by some loaders
    index = HICOLOR / "index.theme"
    dirs = ",".join(f"{s}x{s}/apps" for s in SIZES)
    body = [
        "[Icon Theme]",
        "Name=Hicolor",
        "Comment=Fallback icon theme",
        f"Directories={dirs}",
        "",
    ]
    for s in SIZES:
        body += [
            f"[{s}x{s}/apps]",
            f"Size={s}",
            "Context=Applications",
            "Type=Threshold",
            "",
        ]
    index.write_text("\n".join(body))
    print(f"wrote {index.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
