#!/usr/bin/env python3
"""
MorrowOS "Dawn" palette — single source of truth.

Every other generator (colour scheme, wallpaper, icons) imports from here so
the identity can't drift between files. Run this module directly to print a
WCAG contrast report for every foreground/background pair the UI actually
uses.

Design intent: a deep indigo night with sunrise warmth. Warm accents are used
for focus, selection and links; body text stays a warm near-white so the
accents never have to carry legibility on their own.
"""

# ── core ────────────────────────────────────────────────────────────────────
NIGHT        = "#100E1A"   # deepest — view/input backgrounds
HEADER       = "#0C0A14"   # panel and header bars, darker than the window
INDIGO       = "#171326"   # window background
INDIGO_ALT   = "#201B33"   # alternating rows, raised surfaces
TOOLTIP      = "#241E38"

# ── sunrise accents ─────────────────────────────────────────────────────────
AMBER        = "#F2A65A"   # primary accent: focus, hover, links, selection
CORAL        = "#E8705F"   # secondary accent: active state, warm emphasis
EMBER        = "#C2543F"   # deep accent, for borders and pressed states

# ── text ────────────────────────────────────────────────────────────────────
TEXT         = "#F3ECE3"   # warm near-white, carries all body legibility
TEXT_DIM     = "#A497A8"   # muted, slightly violet so it recedes into indigo
TEXT_ON_SUN  = "#14101F"   # dark text for use ON amber (selection)

# ── semantic ────────────────────────────────────────────────────────────────
POSITIVE     = "#77C486"
NEUTRAL      = "#E8C468"
NEGATIVE     = "#E05C5C"
VISITED      = "#C98BA8"


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_colour: str) -> float:
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (0.2126 * _srgb_to_linear(r)
            + 0.7152 * _srgb_to_linear(g)
            + 0.0722 * _srgb_to_linear(b))


def contrast(fg: str, bg: str) -> float:
    a, b = luminance(fg), luminance(bg)
    lo, hi = min(a, b), max(a, b)
    return (hi + 0.05) / (lo + 0.05)


def rgb(hex_colour: str) -> tuple:
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def kde(hex_colour: str) -> str:
    """KDE .colors files store comma-separated decimal RGB."""
    return ",".join(str(v) for v in rgb(hex_colour))


# Pairs the UI genuinely renders. 4.5 is the WCAG AA threshold for body text,
# 3.0 for large text and for UI component boundaries.
PAIRS = [
    ("body text on window",        TEXT,        INDIGO,     4.5),
    ("body text on view",          TEXT,        NIGHT,      4.5),
    ("body text on alt row",       TEXT,        INDIGO_ALT, 4.5),
    ("body text on header",        TEXT,        HEADER,     4.5),
    ("body text on tooltip",       TEXT,        TOOLTIP,    4.5),
    ("dimmed text on window",      TEXT_DIM,    INDIGO,     4.5),
    ("dimmed text on view",        TEXT_DIM,    NIGHT,      4.5),
    ("link (amber) on window",     AMBER,       INDIGO,     4.5),
    ("link (amber) on view",       AMBER,       NIGHT,      4.5),
    ("active (coral) on window",   CORAL,       INDIGO,     4.5),
    ("text ON amber selection",    TEXT_ON_SUN, AMBER,      4.5),
    ("positive on window",         POSITIVE,    INDIGO,     4.5),
    ("neutral on window",          NEUTRAL,     INDIGO,     4.5),
    ("negative on window",         NEGATIVE,    INDIGO,     4.5),
    ("visited on window",          VISITED,     INDIGO,     4.5),
    ("focus ring on window",       AMBER,       INDIGO,     3.0),
    ("ember border on window",     EMBER,       INDIGO,     3.0),
]


def report() -> int:
    failures = 0
    print(f"{'pair':<30} {'ratio':>7}  {'min':>4}  result")
    print("-" * 56)
    for name, fg, bg, threshold in PAIRS:
        ratio = contrast(fg, bg)
        ok = ratio >= threshold
        if not ok:
            failures += 1
        print(f"{name:<30} {ratio:>6.2f}:1  {threshold:>4.1f}  "
              f"{'PASS' if ok else 'FAIL'}")
    print("-" * 56)
    print("all pass" if failures == 0 else f"{failures} FAILING PAIR(S)")
    return failures


if __name__ == "__main__":
    raise SystemExit(1 if report() else 0)
