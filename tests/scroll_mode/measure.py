#!/usr/bin/env python3
"""Measures a candidate-panel screenshot (2x PNG): the blue highlight capsule, the white text in
it, and the dark ink runs (other candidates) on the capsule's row. Prints points.
  measure.py <image.png> [crop x y w h in points]"""
import struct, sys, zlib

def load(path):
    data = open(path, 'rb').read(); i = 8; idat = b''
    while i < len(data):
        n = struct.unpack('>I', data[i:i + 4])[0]; kind = data[i + 4:i + 8]; chunk = data[i + 8:i + 8 + n]
        if kind == b'IHDR': w, h, _, ct = struct.unpack('>IIBB', chunk[:10])
        if kind == b'IDAT': idat += chunk
        i += 12 + n
    raw = zlib.decompress(idat); bpp = {6: 4, 2: 3}[ct]; stride = w * bpp; rows = []; prev = bytearray(stride); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0; b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(line); prev = line
    return w, h, bpp, rows

w, h, bpp, rows = load(sys.argv[1])
x0, y0, cw, ch = (0, 0, w, h)
if len(sys.argv) == 6:
    x0, y0, cw, ch = (int(float(v) * 2) for v in sys.argv[2:6])
px = lambda x, y: tuple(rows[y][x * bpp:x * bpp + 3])
blue = lambda c: c[0] < 45 and 105 < c[1] < 150 and c[2] > 225  # system blue (#007AFF / #0A84FF), sheen included
dark = lambda c: max(c) < 150 and max(c) - min(c) < 40  # gray or black text, not colored backdrop
white = lambda c: min(c) > 235
xs = range(x0, min(w, x0 + cw)); ys = range(y0, min(h, y0 + ch))
bx = [x for x in xs if any(blue(px(x, y)) for y in ys)]
by = [y for y in ys if any(blue(px(x, y)) for x in xs)]
if not bx:
    sys.exit('no capsule found')
pt = lambda v: v / 2
print('capsule  x %.1f..%.1f (w %.1f)  y %.1f..%.1f (h %.1f)' % (pt(min(bx) - x0), pt(max(bx) + 1 - x0), pt(max(bx) + 1 - min(bx)),
                                                             pt(min(by) - y0), pt(max(by) + 1 - y0), pt(max(by) + 1 - min(by))))
# white ink strictly inside the blue span of each row (the capsule's corners show the backdrop)
wx, wy = [], []
for y in range(min(by) + 2, max(by) - 1):
    span = [x for x in xs if blue(px(x, y))]
    if len(span) < 8: continue
    inside = [x for x in range(min(span) + 2, max(span) - 1) if white(px(x, y))]
    if inside: wx += inside; wy.append(y)
print('white    x %.1f..%.1f  y %.1f..%.1f  padding %.1f / %.1f' % (pt(min(wx) - x0), pt(max(wx) + 1 - x0), pt(min(wy) - y0), pt(max(wy) + 1 - y0),
                                                                  pt(min(wx) - min(bx)), pt(max(bx) - max(wx))))
row = range(min(by), max(by) + 1)
cols = [any(dark(px(x, y)) for y in row) for x in range(max(bx) + 1, min(w, x0 + cw))]
runs, start = [], None
for i, on in enumerate(cols + [False]):
    if on and start is None: start = i
    if not on and start is not None: runs.append((start, i)); start = None
merged = []
for run in runs:
    if merged and run[0] - merged[-1][1] < 5: merged[-1] = (merged[-1][0], run[1])
    else: merged.append(run)
base = max(bx) + 1 - x0
print('ink runs', ' '.join('%.1f-%.1f' % (pt(base + a), pt(base + b)) for a, b in merged))
print('gaps    ', ' '.join('%.1f' % pt(b[0] - a[1]) for a, b in zip(merged, merged[1:])))
ink_rows = [y for y in range(min(by), max(by) + 1) if any(dark(px(x, y)) for x in range(max(bx) + 1, min(w, x0 + cw) - 12))]
if ink_rows:
    top, bottom = pt(min(ink_rows) - y0), pt(max(ink_rows) + 1 - y0)
    print('ink y    %.1f..%.1f (center %.2f)' % (top, bottom, (top + bottom) / 2))
