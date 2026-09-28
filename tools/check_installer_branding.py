#!/usr/bin/env python3
"""
Verify the Calamares installer branding before a build burns 40 minutes.

Calamares parses branding.desc at startup. A syntax error, or an image it
names that is not there, means no working installer -- and you find out only
on the booted ISO, after a full build and a reassembly. This runs in about a
second.

Checks:
  * branding.desc is valid YAML
  * every image it names exists
  * the slideshow QML exists, and every frame it references exists
  * the @VERSION@ placeholder is still present (the build stamps it)
"""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("pyyaml not installed — skipping installer branding check")
    raise SystemExit(0)

D = Path(__file__).resolve().parent.parent / "etc" / "calamares" / "branding" / "morrowos"


def main() -> int:
    desc = D / "branding.desc"
    if not desc.is_file():
        print(f"MISSING {desc}")
        return 1

    text = desc.read_text()
    try:
        b = yaml.safe_load(text)
    except Exception as exc:
        print(f"branding.desc does not parse as YAML:\n  {exc}")
        return 1

    problems = []

    for key, val in (b.get("images") or {}).items():
        if not (D / val).is_file():
            problems.append(f"images.{key} -> {val} does not exist")

    show = b.get("slideshow")
    if not show:
        problems.append("no slideshow declared")
    elif not (D / show).is_file():
        problems.append(f"slideshow {show} does not exist")
    else:
        qml = (D / show).read_text()
        frames = re.findall(r'source:\s*"([^"]+)"', qml)
        if not frames:
            problems.append(f"{show} references no slide images")
        for f in frames:
            if not (D / f).is_file():
                problems.append(f"slide {f} referenced by {show} does not exist")
        if qml.count("{") != qml.count("}"):
            problems.append(f"{show} has unbalanced braces")

    # The build substitutes this. If it is already gone, a stale version
    # number is baked into the repo and every future ISO will advertise it.
    if "@VERSION@" not in text:
        problems.append("branding.desc has no @VERSION@ placeholder — the build "
                        "stamps the real version there")

    for field in ("componentName", "strings"):
        if field not in b:
            problems.append(f"branding.desc has no '{field}'")

    if problems:
        print(f"{len(problems)} problem(s) in the installer branding:")
        for p in problems:
            print(f"  {p}")
        return 1

    n_slides = len(re.findall(r'source:\s*"([^"]+)"', (D / show).read_text()))
    print(f"installer branding OK — {len(b.get('images') or {})} image(s), "
          f"{n_slides} slide(s), component '{b['componentName']}'")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
