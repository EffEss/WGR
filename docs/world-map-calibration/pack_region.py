"""Pack country borders for a single regional Mercator mosaic.

Uses a projection fitted by explore_region.py (plain Mercator: x linear in
longitude, y linear in mercator(latitude)). Clips polygons to the 640x480
raster in PIXEL space, simplifies/quantizes to 1/8 px, and writes a dataset
in the same base64 varint format the HTML decoder already understands.

Usage: python pack_region.py SCRATCH REGION_KEY LON_ORIGIN SX EQUATOR_ROW SY [SIMPLIFY]
                             [--pixel-center]
Output: SCRATCH/REGION_KEY-country-data.json
"""
from pathlib import Path
import argparse
import json
import base64
import numpy as np
from shapely import make_valid, segmentize, transform
from shapely.affinity import translate
from shapely.geometry import box, shape, Polygon
from shapely.geometry.polygon import orient

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("scratch", type=Path)
parser.add_argument("region_key")
parser.add_argument("lon_origin", type=float)
parser.add_argument("sx", type=float)
parser.add_argument("equator_row", type=float)
parser.add_argument("sy", type=float)
parser.add_argument("simplify", type=float, default=0.6, nargs="?")
parser.add_argument("--pixel-center", action="store_true", help="Treat fitted coordinates as pixel indices")
args = parser.parse_args()
root = args.scratch.resolve()

WIDTH, HEIGHT = 640, 480
QUANTIZATION = 8


def project(points):
    lon = points[:, 0]
    lat = np.clip(points[:, 1], -85, 85)
    merc = np.degrees(np.arcsinh(np.tan(np.radians(lat))))
    x = (lon - args.lon_origin) * args.sx
    y = args.equator_row - args.sy * merc
    return np.column_stack((x, y)) + (0.5 if args.pixel_center else 0)


def polygons(geometry):
    if isinstance(geometry, Polygon) and not geometry.is_empty:
        yield geometry
    elif hasattr(geometry, "geoms"):
        for member in geometry.geoms:
            yield from polygons(member)


def quantize(ring):
    pts = []
    for x, y in ring.coords:
        point = (round(x * QUANTIZATION), round(y * QUANTIZATION))
        if not pts or point != pts[-1]:
            pts.append(point)
    if pts and pts[0] == pts[-1]:
        pts.pop()
    return pts


def varint(out, value):
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)


def pack(parts):
    out = bytearray()
    varint(out, len(parts))
    for part in parts:
        varint(out, len(part))
        for ring in part:
            varint(out, len(ring))
            px, py = 0, 0
            for x, y in ring:
                for delta in (x - px, y - py):
                    varint(out, 2 * delta if delta >= 0 else -2 * delta - 1)
                px, py = x, y
    return base64.b64encode(out).decode("ascii")


def frame_parts(geometry):
    projected = transform(segmentize(geometry, 0.4), project)
    period = 360 * args.sx
    for shift in (-period, 0, period):
        local = translate(projected, xoff=shift) if shift else projected
        if local.intersects(frame):
            yield from polygons(make_valid(local).intersection(frame))


source = json.loads((root / "countries.geojson").read_text(encoding="utf8"))
frame = box(0, 0, WIDTH, HEIGHT)
output = []
count = 0
for feature in source["features"]:
    name = feature["properties"]["NAME_LONG"]
    geom = make_valid(shape(feature["geometry"]))
    parts = []
    for poly in frame_parts(geom):
        poly = orient(poly.simplify(args.simplify, preserve_topology=True))
        exterior = quantize(poly.exterior)
        if len(exterior) < 3:
            continue
        holes = [quantize(ring) for ring in poly.interiors]
        parts.append([exterior, *[ring for ring in holes if len(ring) >= 3]])
    if parts:
        output.append((name, pack(parts)))
        count += sum(len(ring) for part in parts for ring in part)

body = ",\n".join(
    json.dumps(row, ensure_ascii=True, separators=(",", ":")) for row in sorted(output))
(root / (args.region_key + "-country-data.json")).write_text(
    "[\n" + body + "\n]", encoding="utf8")
print(len(output), "areas in frame;", count, "projected vertices;", len(body), "inline bytes")
