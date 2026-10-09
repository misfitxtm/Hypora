#!/usr/bin/env python3
"""Check a Hypora theme: every key present, every colour valid, and readable contrast.

    tools/check-theme.py                    # every theme under themes/
    tools/check-theme.py themes/Nord        # just one

A theme is one `colors.toml`, and a missing or unreadable colour does not fail loudly — it
fails as a blank row in the Security window, or grey-on-grey text you only notice at night.
This catches both before anyone sees them.

Contrast is WCAG 2.1 relative luminance. The thresholds are the usual ones, applied to the
pairs Hypora actually renders rather than to every combination:

    foreground on background   4.5   body text
    foreground on surface      4.5   text on panels, popups, the bar
    dim on background          3.0   secondary text — timestamps, hints, inactive items
    accent on background       3.0   a UI component you are meant to find
    error on background        3.0   the one colour that must never be missed

3.0 is the floor for "large text and UI components"; 4.5 is the floor for body text.
A theme can ship below them — this exits non-zero and says so, it does not rewrite anything.
"""
import re
import sys
from pathlib import Path

REQUIRED = [
    "name", "mode",
    "background", "surface", "foreground", "dim", "accent", "error", "selection", "muted",
    "term_foreground",
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "bright_black", "bright_red", "bright_green", "bright_yellow",
    "bright_blue", "bright_magenta", "bright_cyan", "bright_white",
    "font", "gtk_theme", "icon_theme", "color_scheme",
]
COLOUR_KEYS = [k for k in REQUIRED if k not in
               ("name", "mode", "font", "gtk_theme", "icon_theme", "color_scheme")]

# (foreground key, background key, minimum ratio)
CONTRAST = [
    ("foreground", "background", 4.5),
    ("foreground", "surface", 4.5),
    ("dim", "background", 3.0),
    ("accent", "background", 3.0),
    ("error", "background", 3.0),
]

HEX = re.compile(r"\A#[0-9a-fA-F]{6}\Z")


def parse(path):
    """Minimal TOML: `key = "value"` with # comments. The real files are no more than that."""
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r'^([a-z_]+)\s*=\s*"([^"]*)"', line.strip())
        if m:
            out[m.group(1)] = m.group(2)
    return out


def luminance(hex_colour):
    """WCAG relative luminance."""
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    def channel(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = channel(r), channel(g), channel(b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check(theme_dir):
    colours = theme_dir / "colors.toml"
    name = theme_dir.name
    if not colours.is_file():
        print(f"{name}: no colors.toml")
        return 1

    values = parse(colours)
    problems = []

    missing = [k for k in REQUIRED if k not in values]
    if missing:
        problems.append(f"missing key(s): {' '.join(missing)}")

    for k in COLOUR_KEYS:
        v = values.get(k)
        if v is not None and not HEX.match(v):
            problems.append(f"{k} is not a #rrggbb colour: {v!r}")

    if values.get("mode") not in (None, "dark", "light"):
        problems.append(f"mode must be dark or light, not {values['mode']!r}")

    # Wallpapers are optional, but a theme with none falls back to the previous theme's,
    # which looks like a bug rather than a choice.
    shots = theme_dir / "backgrounds"
    n = len([p for p in shots.iterdir()
             if p.suffix.lower() in (".jpg", ".jpeg", ".png")]) if shots.is_dir() else 0

    ratios = []
    for fg, bg, floor in CONTRAST:
        if fg in values and bg in values and HEX.match(values[fg] or "") and HEX.match(values[bg] or ""):
            r = ratio(values[fg], values[bg])
            ratios.append((fg, bg, r, floor))
            if r < floor:
                problems.append(f"{fg} on {bg} is {r:.2f}, below the {floor} floor")

    status = "FAIL" if problems else "ok  "
    detail = "  ".join(f"{fg}/{bg} {r:.1f}" for fg, bg, r, _ in ratios)
    print(f"{status}  {name:<18} {n:>2} wallpapers   {detail}")
    for p in problems:
        print(f"        - {p}")
    return 1 if problems else 0


def main(argv):
    roots = [Path(a) for a in argv[1:]] or sorted(
        d for d in Path("themes").iterdir() if d.is_dir() and d.name != "templates")
    bad = sum(check(d) for d in roots)
    print(f"\n{len(roots) - bad}/{len(roots)} themes pass")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
