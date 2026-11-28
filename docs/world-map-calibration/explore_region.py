"""Exploratory projection fitter for a single regional Sirocco mosaic.

Tests whether a regional 640x480 mosaic (e.g. Europe `eurm`) is a plain
Mercator raster: x linear in longitude, y linear in mercator(latitude).
Fits 4 parameters (lon_origin, x-scale, equator-row, y-scale) by minimizing
the mean distance of Natural Earth boundary vertices to dark border pixels,
then writes an overlay PNG for visual verification.

Usage: python explore_region.py PATH_TO_SCRATCH TARGET.gif LON_MIN LON_MAX LAT_MIN LAT_MAX
"""
from pathlib import Path
import sys, json, math
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, map_coordinates
from scipy.optimize import differential_evolution

if len(sys.argv) != 7:
    sys.exit("Usage: python explore_region.py SCRATCH TARGET.gif LON_MIN LON_MAX LAT_MIN LAT_MAX")
root = Path(sys.argv[1]).resolve()
target = sys.argv[2]
lon_min, lon_max, lat_min, lat_max = map(float, sys.argv[3:7])

WIDTH, HEIGHT = 640, 480

geo = json.loads((root / "countries.geojson").read_text(encoding="utf8"))
from shapely import segmentize
from shapely.geometry import shape, box

clip = box(lon_min, lat_min, lon_max, lat_max)
points = []
for f in geo["features"]:
    g = shape(f["geometry"])
    g = g.intersection(clip)
    if g.is_empty:
        continue
    g = segmentize(g, .2)
    geoms = g.geoms if hasattr(g, "geoms") else [g]
    for poly in geoms:
        if poly.geom_type != "Polygon":
            continue
        points.extend(poly.exterior.coords)
p = np.unique(np.array(points).round(4), axis=0)
rng = np.random.default_rng(4)
if len(p) > 16000:
    p = p[rng.choice(len(p), 16000, replace=False)]
lon = p[:, 0]
merc = np.rad2deg(np.arcsinh(np.tan(np.deg2rad(p[:, 1]))))

img = Image.open(root / target).convert("RGB")
data = np.asarray(img)
darkness = (data.max(axis=2) < 40) & (np.ptp(data.astype("int16"), axis=2) < 24)
dist = np.minimum(distance_transform_edt(~darkness), 8)

# Seed scale ranges from the requested bounding box.
merc_min = math.degrees(math.asinh(math.tan(math.radians(lat_min))))
merc_max = math.degrees(math.asinh(math.tan(math.radians(lat_max))))
sx_guess = WIDTH / (lon_max - lon_min)
sy_guess = HEIGHT / (merc_max - merc_min)


def f(v):
    lon_origin, sx, cy, sy = v
    px = (lon - lon_origin) * sx
    py = cy - sy * merc
    inside = (px > 4) & (px < WIDTH - 4) & (py > 8) & (py < HEIGHT - 8)
    # Score every vertex: on-frame vertices by their distance to dark border
    # pixels, off-frame vertices at the max penalty. This stops the optimizer
    # from cheating by sliding the whole region off-frame.
    scores = np.full(len(px), 8.0)
    if inside.any():
        scores[inside] = map_coordinates(
            dist, np.array([py[inside], px[inside]]), order=1)
    return scores.mean()


bounds = [
    (lon_min - 8, lon_min + 8),
    (sx_guess * 0.6, sx_guess * 1.6),
    (0, HEIGHT * 2.5),
    (sy_guess * 0.5, sy_guess * 1.8),
]
res = differential_evolution(f, bounds, popsize=20, tol=1e-5, seed=83, maxiter=400)
lon_origin, sx, cy, sy = res.x
print(f"{target}: lon_origin={lon_origin:.5f} sx={sx:.5f} equator_row={cy:.5f} sy={sy:.5f}")
print(f"  mean_dist={res.fun:.4f} px  (lower is better; <1 is a strong fit)")
print(f"  west_edge_lon={lon_origin:.4f}  east_edge_lon={lon_origin + WIDTH / sx:.4f}")

canvas = img.resize((1280, 960)).convert("RGB")
draw = ImageDraw.Draw(canvas)
for feature in geo["features"]:
    g = shape(feature["geometry"]).intersection(clip)
    if g.is_empty:
        continue
    geoms = g.geoms if hasattr(g, "geoms") else [g]
    for poly in geoms:
        if poly.geom_type != "Polygon":
            continue
        xs, ys = [], []
        pts = []
        for lng, lat in poly.exterior.coords:
            x = (lng - lon_origin) * sx
            y = cy - sy * math.degrees(math.asinh(math.tan(math.radians(max(-85, min(85, lat))))))
            pts.append((2 * x, 2 * y))
        if len(pts) > 1:
            draw.line(pts, fill="#00f5f0", width=1)
canvas.save(root / ("fit-" + target + ".png"))
print(f"  overlay -> {root / ('fit-' + target + '.png')}")
