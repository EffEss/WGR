"""Overlay a packed regional dataset on an actual Sirocco frame."""
import argparse
import base64
import json
from pathlib import Path
from PIL import Image, ImageDraw
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("scratch", type=Path)
parser.add_argument("key")
parser.add_argument("sample", nargs="?")
args = parser.parse_args()
rows = json.loads((args.scratch / (args.key + "-country-data.json")).read_text(encoding="utf8"))
im = Image.open(args.scratch / (args.sample or args.key + ".gif")).convert("RGB").resize((1280, 960))
d = ImageDraw.Draw(im)


def dec(b):
    buf = base64.b64decode(b)
    i = 0

    def rv():
        nonlocal i
        s = 0
        r = 0
        while True:
            x = buf[i]
            i += 1
            r |= (x & 127) << s
            if x < 128:
                break
            s += 7
        return r

    parts = []
    for _ in range(rv()):
        rings = []
        for _ in range(rv()):
            n = rv()
            px = py = 0
            pts = []
            for _ in range(n):
                dx = rv()
                dy = rv()
                dx = (dx >> 1) if dx % 2 == 0 else -((dx + 1) >> 1)
                dy = (dy >> 1) if dy % 2 == 0 else -((dy + 1) >> 1)
                px += dx
                py += dy
                assert 0 <= px <= 640 * 8 and 0 <= py <= 480 * 8, "vertex outside image"
                pts.append((px / 8, py / 8))
            rings.append(pts)
        parts.append(rings)
    assert i == len(buf), "unused packed border data"
    return parts


for name, b in rows:
    for rings in dec(b):
        for ring in rings:
            if len(ring) > 1:
                d.line([(2 * x, 2 * y) for x, y in ring] + [(2 * ring[0][0], 2 * ring[0][1])],
                       fill="#00f5f0", width=1)
im.save(args.scratch / ("verify-" + args.key + ".png"))
print("saved", len(rows), "areas")
