#!/usr/bin/env python3
"""
Verify every source asset build.sh installs actually exists.

The v1.0 MorrowStore icon bug was exactly this class of problem: the .desktop
file named an icon, the asset sat in the source tree, and nothing connected
them -- discovered only by booting the ISO. This runs in a second instead.

Scans build.sh for install/cp source paths under $SRC and checks each one.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build.sh"

# "$SRC/some/path"  or  "$SRC"/some/path
SRC_REF = re.compile(r'"\$SRC(?:"|)(/[^"\s]+)')

# Paths built inside a loop over $size/$name rather than written literally.
EXPANSIONS = {
    "${size}x${size}": [f"{s}x{s}" for s in (16, 22, 24, 32, 48, 64, 128, 256)],
    "${name}": ["morrowstore", "morrowos-logo"],
}


def expand(path: str):
    out = [path]
    for token, values in EXPANSIONS.items():
        if any(token in p for p in out):
            out = [p.replace(token, v) for p in out for v in values]
    return out


def main() -> int:
    text = BUILD.read_text()
    refs = sorted(set(SRC_REF.findall(text)))
    missing, checked = [], 0

    for ref in refs:
        if "$" in ref and not any(t in ref for t in EXPANSIONS):
            print(f"SKIP (unresolved variable): {ref}")
            continue
        for candidate in expand(ref):
            if "*" in candidate:                      # glob, e.g. morrowstore/*.py
                parent = ROOT / candidate.lstrip("/").rsplit("/", 1)[0]
                pattern = candidate.rsplit("/", 1)[1]
                hits = list(parent.glob(pattern)) if parent.is_dir() else []
                checked += 1
                if not hits:
                    missing.append(candidate)
                continue
            p = ROOT / candidate.lstrip("/")
            checked += 1
            if not p.exists():
                missing.append(candidate)

    print(f"\nchecked {checked} source path(s) referenced by build.sh")
    if missing:
        print(f"\n{len(missing)} MISSING:")
        for m in sorted(set(missing)):
            print(f"  {m}")
        return 1
    print("all present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
