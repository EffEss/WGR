# World map calibration

The World view uses AccuWeather Sirocco's 640×480 Pacific-centered `wmerc` raster. Country hit areas come from Natural Earth's 1:50m admin-0 countries and territories. The calibrated coverage applies to `wmerc` only. Dedicated regional mosaics have their own image geometry, and the U.S. Lambert Conformal Conic calibration stays in place.

## Measured fit

The fitter sampled Natural Earth boundary vertices and minimized their mean distance to dark border pixels, with distances capped at eight pixels. It sampled inside the raster margins and checked the projected outlines visually in the three saved images. The distance is a fitting score against raster edges.

| Saved sample | West seam (°E) | X pixels per degree | Equator row from top | Y pixels per Mercator degree | Mean distance (px) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Enhanced IR still | 75.35168 | 1.778323 | 240.16190 | 2.664438 | 0.28330 |
| Standard IR still | 75.35168 | 1.778323 | 240.16190 | 2.664438 | 0.28330 |
| Enhanced IR loop, first frame | 75.35006 | 1.778312 | 240.17448 | 2.664675 | 0.28308 |

The shipped fit uses a seam of **75.4°E**, a width of exactly **640 px per 360°**, an equator row of **240.16 px**, and **2.6645 px per Mercator degree** vertically. The exact world width keeps copies aligned when panning. For longitude `lon` and latitude `lat` in degrees:

```text
x = positiveModulo(lon - 75.4, 360) * 640 / 360
mercatorDegrees = degrees(asinh(tan(radians(lat))))
leafletY = 480 - 240.16 + 2.6645 * mercatorDegrees
```

The raster ends near ±66.5°. The app draws outlines past those edges and labels the lack of polar imagery. For outline coordinates beyond ±85°, the packer and HTML use a linear continuation with 2.2 Mercator degrees per latitude degree. The renderer wraps every 640 px. The packer clips polygons at 75.4°E, and the app reunites the relevant bounds across the seam when zooming to a country.

## Reproducing or updating the geometry

The saved November 22, 2026 calibration bundle is in the experiment copy at `.world-projection-work/`. It contains the exact source GeoJSON, live GIF snapshots, fit outputs, and overlay PNGs. In particular, `fit-world.gif.png` shows the enhanced IR outline alignment, and `browser-preview.png` is a UI capture. The repo can also regenerate geometry from fresh downloads.

Put these files in a scratch directory:

| Name | Source |
| --- | --- |
| `countries.geojson` | [Natural Earth 1:50m admin-0 GeoJSON](https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson) |
| `world.gif` | [Enhanced IR still](https://sirocco.accuweather.com/sat_mosaic_640x480_public/ei/isewmerc.gif) |
| `world_ir.gif` | [Standard IR still](https://sirocco.accuweather.com/sat_mosaic_640x480_public/ir/iswmerc.gif) |
| `world_loop.gif` | [Enhanced IR loop](https://sirocco.accuweather.com/sat_mosaic_640x480_public/ei/isaewmerc.gif) |

The [sample manifest](world-map-calibration/samples.json) records SHA-256 hashes and fitted parameters. Sirocco GIF contents change with each update. [Natural Earth data is public domain](https://www.naturalearthdata.com/about/terms-of-use/).

From the repository root:

```powershell
python -m pip install numpy scipy Pillow shapely
python docs/world-map-calibration/fit.py PATH_TO_SCRATCH
python docs/world-map-calibration/pack.py PATH_TO_SCRATCH
```

`fit.py` writes the fitted values and overlay PNGs to the scratch directory. `pack.py` uses the shipped fit, simplifies and quantizes the projected polygons to 1/8 px, and writes `world-country-data.json`. Replace the JSON inside `<script id="worldCountryData" type="application/json">` in `Assets/radar-map.html` with that output when updating the dataset. If the fit changes, update the constants in both the packer and HTML before regenerating the data. The shipped snapshot contains 242 named areas and 23,290 projected vertices.
