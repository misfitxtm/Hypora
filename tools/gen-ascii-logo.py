#!/usr/bin/env python3
"""Regenerate config/fastfetch/hypora.txt from the Hypora mark.

The ASCII logo is a rasterisation of the same geometry config/quickshell/Logo.qml
draws as an SVG, mapped onto a character grid the way Fedora's fetch logo is: a
uniform fill character for solid coverage, lighter punctuation on the edges, and
dense capitals for the H and its aurora crossbar on top.

It is generated rather than hand-drawn because hand-drawing it does not work --
the slopes and the stroke positions have to come off the real geometry or the
mark just reads as a blob. If Logo.qml's shape ever changes, change HEX/GLYPH to
match and re-run this; do not edit hypora.txt by hand.

    python3 tools/gen-ascii-logo.py            # write the file
    python3 tools/gen-ascii-logo.py --preview   # print it in colour instead
"""

import argparse
import math
import os

# --- geometry, kept in step with config/quickshell/Logo.qml (viewBox 0 0 24 24) ---

HEX = [(12, 1.8), (20.8, 6.9), (20.8, 17.1), (12, 22.2), (3.2, 17.1), (3.2, 6.9)]
STROKE = 1.9

COLS, ROWS = 34, 20

# A terminal cell is about twice as tall as it is wide, so the crossbar's 1.9-unit
# stroke is only ~1.7 rows thick while its whole rise is ~2 rows -- at this size the
# curve flattens into a straight bar. Exaggerating it is what redrawing a mark small
# normally involves; 1.5 reads as a wave, and by 1.9 it starts tearing a gap in the
# upright it joins.
WAVE_GAIN = 1.5


def cubic(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append((
            u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
            u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
        ))
    return pts


def wave():
    """Logo.qml's `M8.4 12 c1.2-1.7 2.4-1.7 3.6 0 s2.4 1.7 3.6 0`, flattened."""
    a = cubic((8.4, 12), (9.6, 10.3), (10.8, 10.3), (12, 12))
    # `s` reflects the previous control point through the join
    b = cubic((12, 12), (13.2, 13.7), (14.4, 13.7), (15.6, 12))
    pts = a + b[1:]
    return [(x, 12 + (y - 12) * WAVE_GAIN) for x, y in pts]


# the two uprights of the H, plus the crossbar
GLYPH = [[(8.4, 7.6), (8.4, 16.4)], [(15.6, 7.6), (15.6, 16.4)], wave()]


def inside(pt, poly):
    x, y = pt
    hit = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) / (y1 - y0) * (x1 - x0):
            hit = not hit
    return hit


def seg_dist(pt, a, b):
    px, py = pt
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0.0 if length == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def on_glyph(pt, r):
    return any(
        seg_dist(pt, poly[i], poly[i + 1]) <= r
        for poly in GLYPH
        for i in range(len(poly) - 1)
    )


# Coverage -> character. The edge characters are picked by where inside the cell the
# coverage actually sits, so a top edge gets a high glyph and a bottom edge a low one;
# that is what keeps the hexagon's points from looking chewed.
def body_char(cov, vy):
    if cov >= 0.80:
        return 'c'
    if cov >= 0.45:
        return ':' if 0.25 < vy < 0.75 else ("'" if vy < 0.5 else ',')
    return "'" if vy < 0.35 else ('.' if vy > 0.65 else ':')


def glyph_char(cov, vy):
    if cov >= 0.80:
        return 'M'
    if cov >= 0.55:
        return 'W'
    if cov >= 0.30:
        return 'o' if vy > 0.5 else 'x'
    return "'" if vy < 0.35 else ('.' if vy > 0.65 else ':')


def render(cols=COLS, rows=ROWS, ss_x=4, ss_y=8):
    """Return rows of (char, kind) with kind in {'body', 'glyph', None}."""
    r = STROKE / 2
    x0, x1 = 3.2 - r, 20.8 + r
    y0, y1 = 1.8 - r, 22.2 + r
    out = []
    for ry in range(rows):
        line = []
        for rx in range(cols):
            nb = ng = tot = 0
            vy_b = vy_g = 0.0
            for sy in range(ss_y):
                for sx in range(ss_x):
                    u = (rx + (sx + 0.5) / ss_x) / cols
                    v = (ry + (sy + 0.5) / ss_y) / rows
                    pt = (x0 + u * (x1 - x0), y0 + v * (y1 - y0))
                    tot += 1
                    frac = (sy + 0.5) / ss_y
                    if on_glyph(pt, r):
                        ng += 1
                        vy_g += frac
                    elif inside(pt, HEX):
                        nb += 1
                        vy_b += frac
            cg, cb = ng / tot, nb / tot
            if cg > 0.04:
                line.append((glyph_char(cg, vy_g / ng), 'glyph'))
            elif cb > 0.04:
                line.append((body_char(cb, vy_b / nb), 'body'))
            else:
                line.append((' ', None))
        out.append(line)
    while out and not any(k for _, k in out[0]):
        out.pop(0)
    while out and not any(k for _, k in out[-1]):
        out.pop()
    return out


def to_text(grid, c1='$1', c2='$2'):
    """Emit with fastfetch colour placeholders: $1 the hexagon, $2 the H.

    fastfetch resets the colour at every newline, so each line re-states $1 rather
    than relying on the previous line's.
    """
    lines = []
    for row in grid:
        buf = []
        cur = None
        for ch, kind in row:
            want = c2 if kind == 'glyph' else c1
            if want != cur:
                buf.append(want)
                cur = want
            buf.append(ch)
        lines.append(''.join(buf).rstrip())
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preview', action='store_true', help='print in colour, write nothing')
    args = ap.parse_args()

    grid = render()
    if args.preview:
        print(to_text(grid, '\033[38;2;122;162;247m', '\033[38;2;195;122;247m').replace('\n', '\033[0m\n'))
        return

    dest = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        'config', 'fastfetch', 'hypora.txt')
    with open(dest, 'w') as fh:
        fh.write(to_text(grid))
    plain = max(len(l.replace('$1', '').replace('$2', '')) for l in to_text(grid).splitlines())
    print(f'wrote {dest} ({plain} cols x {len(grid)} rows)')


if __name__ == '__main__':
    main()
